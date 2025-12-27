#!/bin/bash
set -euo pipefail

# Script to extend the persistent partition to use full disk space
# This script is called during the network stage for cloud images
# It extends COS_PERSISTENT after COS_CONTENT has been deleted

# Log file path
LOG_FILE="/var/log/persistent-extension.log"

# Function to log messages to both stdout and log file
log() {
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$message"
  echo "$message" >> "$LOG_FILE" 2>&1 || true
}

# Function to log errors
log_error() {
  local message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
  echo "$message" >&2
  echo "$message" >> "$LOG_FILE" 2>&1 || true
}

# Create log file directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")" || true

log "=== Persistent Partition Extension Script ==="
log "Timestamp: $(date)"

# Find the persistent partition
PERSISTENT_PARTITION=$(blkid -L COS_PERSISTENT 2>/dev/null || findfs PARTLABEL=persistent 2>/dev/null || true)
if [ -z "$PERSISTENT_PARTITION" ]; then
  log_error "No persistent partition found, skipping extension"
  exit 0
fi

log "Found persistent partition: $PERSISTENT_PARTITION"

# Extract disk device and partition number
if [[ "$PERSISTENT_PARTITION" =~ ^/dev/nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
  PARTITION_NUM="${BASH_REMATCH[1]}"
  DISK_DEV=$(echo "$PERSISTENT_PARTITION" | sed 's/p[0-9]*$//')
elif [[ "$PERSISTENT_PARTITION" =~ ^/dev/([a-z]+)([0-9]+)$ ]]; then
  DISK_BASE="${BASH_REMATCH[1]}"
  PARTITION_NUM="${BASH_REMATCH[2]}"
  DISK_DEV="/dev/$DISK_BASE"
else
  log_error "Could not parse partition device: $PERSISTENT_PARTITION"
  exit 0
fi

log "Disk device: $DISK_DEV, Partition number: $PARTITION_NUM"

# Check if content partition still exists
CONTENT_PARTITION=$(blkid -L COS_CONTENT 2>/dev/null || findfs PARTLABEL=COS_CONTENT 2>/dev/null || true)
if [ -n "$CONTENT_PARTITION" ]; then
  log "WARNING: Content partition still exists: $CONTENT_PARTITION"
  log "Will extend persistent up to content partition start"
  if [[ "$CONTENT_PARTITION" =~ ^/dev/nvme[0-9]+n[0-9]+p([0-9]+)$ ]]; then
    CONTENT_PART_NUM="${BASH_REMATCH[1]}"
  elif [[ "$CONTENT_PARTITION" =~ ^/dev/([a-z]+)([0-9]+)$ ]]; then
    CONTENT_PART_NUM="${BASH_REMATCH[2]}"
  fi
  if [ -n "${CONTENT_PART_NUM:-}" ] && command -v parted >/dev/null 2>&1; then
    CONTENT_START=$(parted -s "$DISK_DEV" unit s print 2>>"$LOG_FILE" | grep "^ *$CONTENT_PART_NUM" | awk '{print $2}' | sed 's/s$//')
    NEW_END=$(($CONTENT_START - 1))
    log "Will extend persistent to end at sector $NEW_END (just before content partition)"
  else
    log_error "Cannot determine content partition start"
    exit 0
  fi
else
  log "Content partition has been deleted, extending persistent to use full disk"
  NEW_END=""
fi

# Extend partition
EXTENDED=false
if command -v growpart >/dev/null 2>&1; then
  log "Extending partition $PARTITION_NUM on $DISK_DEV using growpart..."
  if growpart "$DISK_DEV" "$PARTITION_NUM" 2>>"$LOG_FILE"; then
    log "Partition extended successfully using growpart"
    EXTENDED=true
  else
    log "growpart failed, trying parted..."
  fi
fi

# Fallback to parted
if [ "$EXTENDED" = "false" ] && command -v parted >/dev/null 2>&1; then
  log "Extending partition $PARTITION_NUM on $DISK_DEV using parted..."
  CURRENT_END=$(parted -s "$DISK_DEV" unit s print 2>>"$LOG_FILE" | grep "^ *$PARTITION_NUM" | awk '{print $3}' | sed 's/s$//')
  
  if [ -z "${NEW_END:-}" ]; then
    DISK_END=$(parted -s "$DISK_DEV" unit s print 2>>"$LOG_FILE" | grep "Disk $DISK_DEV" | awk '{print $3}' | sed 's/s$//')
    NEW_END=$(($DISK_END - 34))  # Leave space for GPT backup
  fi
  
  if [ "$NEW_END" -gt "$CURRENT_END" ]; then
    log "Extending partition from sector $CURRENT_END to sector $NEW_END"
    if parted -s "$DISK_DEV" resizepart "$PARTITION_NUM" "${NEW_END}s" 2>>"$LOG_FILE"; then
      log "Partition extended successfully using parted"
      EXTENDED=true
    else
      log_error "Failed to extend partition using parted"
      exit 0
    fi
  else
    log "Partition already at maximum size"
    EXTENDED=true
  fi
fi

if [ "$EXTENDED" = "true" ]; then
  log "Resizing filesystem on $PERSISTENT_PARTITION..."
  
  # Unmount if mounted
  MOUNT_POINT=""
  if mount | grep -q "$PERSISTENT_PARTITION"; then
    MOUNT_POINT=$(mount | grep "$PERSISTENT_PARTITION" | awk '{print $3}' | head -1)
    log "Unmounting $PERSISTENT_PARTITION from $MOUNT_POINT"
    umount "$PERSISTENT_PARTITION" 2>>"$LOG_FILE" || {
      log "WARNING: Could not unmount, trying to resize online..."
    }
  fi
  
  # Get filesystem type
  FSTYPE=$(blkid -s TYPE -o value "$PERSISTENT_PARTITION" 2>/dev/null || echo "ext2")
  log "Filesystem type: $FSTYPE"
  
  # Resize filesystem
  case "$FSTYPE" in
    ext2|ext3|ext4)
      if command -v resize2fs >/dev/null 2>&1; then
        if resize2fs "$PERSISTENT_PARTITION" 2>>"$LOG_FILE"; then
          log "Filesystem resized successfully"
        else
          log_error "Failed to resize ext filesystem"
          exit 0
        fi
      else
        log_error "resize2fs not found"
        exit 0
      fi
      ;;
    xfs)
      if command -v xfs_growfs >/dev/null 2>&1; then
        if xfs_growfs "$PERSISTENT_PARTITION" 2>>"$LOG_FILE"; then
          log "Filesystem resized successfully"
        else
          log_error "Failed to resize xfs filesystem"
          exit 0
        fi
      else
        log_error "xfs_growfs not found"
        exit 0
      fi
      ;;
    *)
      log_error "Unknown filesystem type $FSTYPE"
      exit 0
      ;;
  esac
  
  # Remount if it was mounted
  if [ -n "${MOUNT_POINT:-}" ] && [ -d "$MOUNT_POINT" ]; then
    log "Remounting $PERSISTENT_PARTITION to $MOUNT_POINT"
    mount "$PERSISTENT_PARTITION" "$MOUNT_POINT" 2>>"$LOG_FILE" || true
  fi
  
  log "=== Extension Complete ==="
  exit 0
else
  log_error "Could not extend partition (growpart and parted not available)"
  exit 0
fi

