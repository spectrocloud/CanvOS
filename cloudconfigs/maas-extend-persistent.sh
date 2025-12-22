#!/bin/bash
set -euo pipefail

# Script to extend the persistent partition by reclaiming space from:
# 1. Ubuntu rootfs partition (UBUNTU_ROOTFS) - removed during boot
# 2. Content partition (COS_CONTENT) - removed after content extraction
#
# This script should be run after content extraction is complete

# Log file path
LOG_FILE="/var/log/stylus-maas-extend-persistent.log"

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

log "Starting persistent partition extension script"

# Find the persistent partition
PERSISTENT_PARTITION=$(blkid -L COS_PERSISTENT 2>/dev/null || true)
if [ -z "$PERSISTENT_PARTITION" ]; then
  log_error "Persistent partition (COS_PERSISTENT) not found, cannot extend"
  exit 1
fi

log "Found persistent partition: $PERSISTENT_PARTITION"

# Get partition number and disk device for persistent partition
# Handle various disk device types:
# - NVMe: /dev/nvme0n1p5
# - Virtio (KVM/QEMU/LXD): /dev/vda5
# - Xen: /dev/xvda5
# - SCSI/SATA (physical or VM): /dev/sda5
if [[ "$PERSISTENT_PARTITION" =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then
  # NVMe format: /dev/nvme0n1p5
  PERSISTENT_PART_NUM=$(echo "$PERSISTENT_PARTITION" | grep -oE '[0-9]+$')
  DISK_DEV=$(echo "$PERSISTENT_PARTITION" | sed 's/p[0-9]*$//')
  DISK_TYPE="NVMe"
elif [[ "$PERSISTENT_PARTITION" =~ ^/dev/vd[a-z][0-9]+$ ]]; then
  # Virtio format: /dev/vda5
  PERSISTENT_PART_NUM=$(echo "$PERSISTENT_PARTITION" | grep -oE '[0-9]+$')
  DISK_DEV=$(echo "$PERSISTENT_PARTITION" | sed 's/[0-9]*$//')
  DISK_TYPE="Virtio (KVM/QEMU/LXD)"
elif [[ "$PERSISTENT_PARTITION" =~ ^/dev/xvd[a-z][0-9]+$ ]]; then
  # Xen format: /dev/xvda5
  PERSISTENT_PART_NUM=$(echo "$PERSISTENT_PARTITION" | grep -oE '[0-9]+$')
  DISK_DEV=$(echo "$PERSISTENT_PARTITION" | sed 's/[0-9]*$//')
  DISK_TYPE="Xen"
elif [[ "$PERSISTENT_PARTITION" =~ ^/dev/[a-z]+[0-9]+$ ]]; then
  # Standard format: /dev/sda5, /dev/hda5, etc.
  PERSISTENT_PART_NUM=$(echo "$PERSISTENT_PARTITION" | grep -oE '[0-9]+$')
  DISK_DEV=$(echo "$PERSISTENT_PARTITION" | sed 's/[0-9]*$//')
  DISK_TYPE="SCSI/SATA"
else
  log_error "Unknown disk device format: $PERSISTENT_PARTITION"
  exit 1
fi

log "Disk type: $DISK_TYPE"
log "Disk device: $DISK_DEV, Persistent partition number: $PERSISTENT_PART_NUM"

# Get current partition info
PERSISTENT_PART_INFO=$(parted -s "$DISK_DEV" unit MiB print | grep "^[[:space:]]*${PERSISTENT_PART_NUM}[[:space:]]" || true)
if [ -z "$PERSISTENT_PART_INFO" ]; then
  log_error "Could not get persistent partition information"
  exit 1
fi

PERSISTENT_PART_START=$(echo "$PERSISTENT_PART_INFO" | awk '{print $2}' | sed 's/MiB//')
PERSISTENT_PART_END=$(echo "$PERSISTENT_PART_INFO" | awk '{print $3}' | sed 's/MiB//')
log "Current persistent partition: ${PERSISTENT_PART_START}MiB to ${PERSISTENT_PART_END}MiB"

# Get disk size
DISK_SIZE=$(parted -s "$DISK_DEV" unit MiB print | grep "^Disk /" | awk '{print $3}' | sed 's/MiB//')
log "Disk size: ${DISK_SIZE}MiB"

# Check for partitions that should be removed (if they still exist)
PARTITIONS_TO_REMOVE=()

# Check for Ubuntu rootfs partition
UBUNTU_PARTITION=$(blkid -L UBUNTU_ROOTFS 2>/dev/null || true)
if [ -n "$UBUNTU_PARTITION" ]; then
  log "Found Ubuntu rootfs partition that should be removed: $UBUNTU_PARTITION"
  PARTITIONS_TO_REMOVE+=("$UBUNTU_PARTITION")
fi

# Check for content partition
CONTENT_PARTITION=$(blkid -L COS_CONTENT 2>/dev/null || true)
if [ -n "$CONTENT_PARTITION" ]; then
  log "Found content partition that should be removed: $CONTENT_PARTITION"
  PARTITIONS_TO_REMOVE+=("$CONTENT_PARTITION")
fi

# Remove partitions if they still exist
for PARTITION in "${PARTITIONS_TO_REMOVE[@]}"; do
  log "Processing partition for removal: $PARTITION"
  
  # Get partition number (same logic as persistent partition)
  if [[ "$PARTITION" =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then
    # NVMe format
    PART_NUM=$(echo "$PARTITION" | grep -oE '[0-9]+$')
  elif [[ "$PARTITION" =~ ^/dev/vd[a-z][0-9]+$ ]] || [[ "$PARTITION" =~ ^/dev/xvd[a-z][0-9]+$ ]] || [[ "$PARTITION" =~ ^/dev/[a-z]+[0-9]+$ ]]; then
    # Virtio, Xen, or standard format
    PART_NUM=$(echo "$PARTITION" | grep -oE '[0-9]+$')
  else
    log_error "Unknown partition format: $PARTITION"
    continue
  fi
  
  log "Partition number: $PART_NUM"
  
  # Wipe filesystem signatures
  if command -v wipefs >/dev/null 2>&1; then
    log "Wiping filesystem signatures from $PARTITION"
    wipefs -a "$PARTITION" 2>>"$LOG_FILE" || log "Warning: Failed to wipe filesystem signatures"
  fi
  
  # Remove partition from partition table
  log "Removing partition $PART_NUM from $DISK_DEV"
  if parted -s "$DISK_DEV" rm "$PART_NUM" 2>>"$LOG_FILE"; then
    log "Successfully removed partition $PART_NUM"
  else
    log "Warning: Failed to remove partition $PART_NUM (may already be removed or in use)"
  fi
done

# Force re-read of partition table after removals
if [ ${#PARTITIONS_TO_REMOVE[@]} -gt 0 ]; then
  log "Re-reading partition table after partition removals"
  partprobe "$DISK_DEV" 2>/dev/null || true
  sleep 2
  
  # Re-read persistent partition info after removals
  PERSISTENT_PART_INFO=$(parted -s "$DISK_DEV" unit MiB print | grep "^[[:space:]]*${PERSISTENT_PART_NUM}[[:space:]]" || true)
  if [ -n "$PERSISTENT_PART_INFO" ]; then
    PERSISTENT_PART_END=$(echo "$PERSISTENT_PART_INFO" | awk '{print $3}' | sed 's/MiB//')
    log "Persistent partition end after removals: ${PERSISTENT_PART_END}MiB"
  fi
fi

# Find the next partition after persistent (if any)
NEXT_PART_NUM=$(parted -s "$DISK_DEV" unit MiB print | awk -v pnum="$PERSISTENT_PART_NUM" '/^[[:space:]]*[0-9]+[[:space:]]/ {if ($1 > pnum && $1 != pnum) {print $1; exit}}')

if [ -n "$NEXT_PART_NUM" ]; then
  # There's a partition after persistent, extend to just before it
  NEXT_PART_INFO=$(parted -s "$DISK_DEV" unit MiB print | grep "^[[:space:]]*${NEXT_PART_NUM}[[:space:]]" || true)
  if [ -n "$NEXT_PART_INFO" ]; then
    NEXT_PART_START=$(echo "$NEXT_PART_INFO" | awk '{print $2}' | sed 's/MiB//')
    NEW_PERSISTENT_END=$NEXT_PART_START
    log "Next partition starts at ${NEXT_PART_START}MiB, extending persistent to ${NEW_PERSISTENT_END}MiB"
  else
    # Fallback: extend to end of disk
    NEW_PERSISTENT_END=$DISK_SIZE
    log "Could not determine next partition, extending persistent to end of disk: ${NEW_PERSISTENT_END}MiB"
  fi
else
  # No partition after persistent, extend to end of disk
  NEW_PERSISTENT_END=$DISK_SIZE
  log "No partition after persistent, extending to end of disk: ${NEW_PERSISTENT_END}MiB"
fi

# Check if we actually need to extend
if [ "$PERSISTENT_PART_END" -ge "$NEW_PERSISTENT_END" ]; then
  log "Persistent partition is already at maximum size (${PERSISTENT_PART_END}MiB >= ${NEW_PERSISTENT_END}MiB), no extension needed"
  exit 0
fi

# Check if partition is mounted
MOUNT_POINT=$(mount | grep "$PERSISTENT_PARTITION" | awk '{print $3}' | head -n1 || true)
IS_MOUNTED=false
if [ -n "$MOUNT_POINT" ]; then
  IS_MOUNTED=true
  log "Persistent partition is mounted at: $MOUNT_POINT"
else
  log "Persistent partition is not mounted"
fi

# Resize the partition (this works even if mounted - it just updates the partition table)
log "Resizing persistent partition from ${PERSISTENT_PART_END}MiB to ${NEW_PERSISTENT_END}MiB"
if ! parted -s "$DISK_DEV" unit MiB resizepart "$PERSISTENT_PART_NUM" "$NEW_PERSISTENT_END" 2>>"$LOG_FILE"; then
  log_error "Failed to resize persistent partition"
  exit 1
fi

# Resize the filesystem
log "Resizing filesystem on $PERSISTENT_PARTITION"
# Force a re-read of the partition table
partprobe "$DISK_DEV" 2>/dev/null || true
sleep 2

# Check filesystem type and resize accordingly
FS_TYPE=$(blkid -o value -s TYPE "$PERSISTENT_PARTITION" 2>/dev/null || echo "")
if [ "$FS_TYPE" = "ext4" ] || [ "$FS_TYPE" = "ext2" ] || [ "$FS_TYPE" = "ext3" ]; then
  # Resize ext2/3/4 filesystem
  if [ "$IS_MOUNTED" = "true" ]; then
    # Online resize for mounted ext4 filesystems (ext4 supports online grow)
    log "Performing online resize of mounted ext4 filesystem"
    if ! resize2fs "$PERSISTENT_PARTITION" 2>>"$LOG_FILE"; then
      log_error "Failed to resize mounted filesystem"
      exit 1
    fi
  else
    # Offline resize - can run e2fsck first for safety
    log "Performing offline resize of unmounted ext4 filesystem"
    e2fsck -f -y "$PERSISTENT_PARTITION" 2>>"$LOG_FILE" || log "Warning: e2fsck had issues, continuing anyway"
    if ! resize2fs "$PERSISTENT_PARTITION" 2>>"$LOG_FILE"; then
      log_error "Failed to resize filesystem"
      exit 1
    fi
  fi
  log "✅ Persistent partition extended successfully"
elif [ "$FS_TYPE" = "xfs" ]; then
  # Resize XFS filesystem (xfs_growfs supports online resize)
  if [ "$IS_MOUNTED" = "true" ]; then
    # xfs_growfs works on mounted filesystems, but needs the mount point
    log "Performing online resize of mounted XFS filesystem"
    if ! xfs_growfs "$MOUNT_POINT" 2>>"$LOG_FILE"; then
      log_error "Failed to resize mounted XFS filesystem"
      exit 1
    fi
  else
    log "Performing offline resize of unmounted XFS filesystem"
    if ! xfs_growfs "$PERSISTENT_PARTITION" 2>>"$LOG_FILE"; then
      log_error "Failed to resize XFS filesystem"
      exit 1
    fi
  fi
  log "✅ Persistent partition extended successfully"
else
  log_error "Unknown filesystem type '$FS_TYPE', skipping filesystem resize"
  log "Partition was resized, but filesystem resize may be needed manually"
  exit 1
fi

# Verify the new size
NEW_SIZE=$(df -h "$PERSISTENT_PARTITION" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
log "Persistent partition new size: $NEW_SIZE"

log "Persistent partition extension completed successfully"
exit 0

