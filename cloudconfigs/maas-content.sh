#!/bin/bash
set -euo pipefail

# Script to extract content and SPC from COS_CONTENT partition
# This script is called from 80_stylus_maas.yaml during the network stage
# Note: local-ui is handled directly in the iso-image build, not via content partition

# Log file path
LOG_FILE="/var/logs/stylus-maas-content-script.log"

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

log "Starting content extraction script"

# Find the partition with COS_CONTENT label
CONTENT_PARTITION=$(blkid -L COS_CONTENT 2>/dev/null || true)
if [ -z "$CONTENT_PARTITION" ]; then
  log "No content partition found with label COS_CONTENT, skipping content extraction"
  exit 0
fi

log "Found content partition: $CONTENT_PARTITION"

# Create mount point
CONTENT_MOUNT="/opt/spectrocloud/content"
mkdir -p "$CONTENT_MOUNT"
log "Created mount point: $CONTENT_MOUNT"

# Mount the content partition
log "Mounting content partition $CONTENT_PARTITION to $CONTENT_MOUNT"
mount -t ext4 "$CONTENT_PARTITION" "$CONTENT_MOUNT" || {
  log_error "Failed to mount content partition"
  exit 1
}
log "Successfully mounted content partition"

# Create destination directories
CONTENT_DEST="/usr/local/spectrocloud/bundle"
CLUSTER_CONFIG_COPY_DIR="/usr/local/spectrocloud/clusterconfig"
mkdir -p "$CONTENT_DEST"
mkdir -p "$CLUSTER_CONFIG_COPY_DIR"
log "Created destination directories: $CONTENT_DEST and $CLUSTER_CONFIG_COPY_DIR"

# Extract .zst and .tar files from partition, copy .tgz files (SPC) directly
log "Extracting files from content partition..."

# Initialize counters
ZST_COUNT=0
TAR_COUNT=0
SPC_COUNT=0

# Process all files in the content partition
for file in "$CONTENT_MOUNT"/*; do
  if [ -f "$file" ]; then
    FILENAME=$(basename "$file")
    EXTENSION="${FILENAME##*.}"
    
    # Handle .tgz files - these are SPC files, copy them directly (don't extract)
    if [ "$EXTENSION" = "tgz" ] || [[ "$FILENAME" =~ \.tar\.gz$ ]]; then
      log "Copying SPC file (.tgz): $FILENAME"
      if cp "$file" "$CLUSTER_CONFIG_COPY_DIR/$FILENAME" 2>>"$LOG_FILE"; then
        log "Successfully copied SPC file to $CLUSTER_CONFIG_COPY_DIR/$FILENAME"
        SPC_COUNT=$((SPC_COUNT + 1))
      else
        log_error "Failed to copy SPC file: $FILENAME"
      fi
      continue
    fi
    
    # Handle .zst files - extract them to bundle directory
    if [ "$EXTENSION" = "zst" ]; then
      log "Extracting .zst file: $FILENAME"
      if zstd -d -f "$file" -o "$CONTENT_DEST/${FILENAME%.zst}" 2>>"$LOG_FILE"; then
        log "Successfully extracted $FILENAME"
        ZST_COUNT=$((ZST_COUNT + 1))
      else
        log_error "Failed to extract $FILENAME, copying as-is"
        cp "$file" "$CONTENT_DEST/$FILENAME" || {
          log_error "Failed to copy $FILENAME"
        }
      fi
      continue
    fi
    
    # Handle .tar files - extract them to bundle directory
    if [ "$EXTENSION" = "tar" ]; then
      log "Extracting .tar file: $FILENAME"
      if tar -xf "$file" -C "$CONTENT_DEST" 2>>"$LOG_FILE"; then
        log "Successfully extracted $FILENAME"
        TAR_COUNT=$((TAR_COUNT + 1))
      else
        log_error "Failed to extract $FILENAME, copying as-is"
        cp "$file" "$CONTENT_DEST/$FILENAME" || {
          log_error "Failed to copy $FILENAME"
        }
      fi
      continue
    fi
    
    # For any other files, log a warning but don't process
    log "Skipping file with unknown extension: $FILENAME (extension: $EXTENSION)"
  fi
done

log "Extraction summary: $ZST_COUNT .zst file(s), $TAR_COUNT .tar file(s) extracted, $SPC_COUNT .tgz file(s) (SPC) copied"

# Unmount the content partition
log "Unmounting content partition"
umount "$CONTENT_MOUNT" || {
  log_error "Failed to unmount content partition"
  exit 1
}
rmdir "$CONTENT_MOUNT" || true
log "Successfully unmounted content partition"

# Delete the content partition after successful extraction
log "Deleting content partition: $CONTENT_PARTITION"
# Get the disk device and partition number
# For /dev/sda5 -> DISK_DEVICE=/dev/sda, PARTITION_NUM=5
# For /dev/nvme0n1p5 -> DISK_DEVICE=/dev/nvme0n1, PARTITION_NUM=5
# Extract partition number (last sequence of digits)
PARTITION_NUM=$(echo "$CONTENT_PARTITION" | grep -oE '[0-9]+$')
# Extract disk device by removing the partition number
if [[ "$CONTENT_PARTITION" =~ ^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
  # NVMe format: /dev/nvme0n1p5
  DISK_DEVICE=$(echo "$CONTENT_PARTITION" | sed 's/p[0-9]*$//')
else
  # Standard format: /dev/sda5
  DISK_DEVICE=$(echo "$CONTENT_PARTITION" | sed 's/[0-9]*$//')
fi

if [ -n "$DISK_DEVICE" ] && [ -n "$PARTITION_NUM" ]; then
  log "Disk device: $DISK_DEVICE, Partition number: $PARTITION_NUM"
  
  # Wipe filesystem signatures from the partition
  if command -v wipefs >/dev/null 2>&1; then
    log "Wiping filesystem signatures from partition"
    wipefs -a "$CONTENT_PARTITION" 2>>"$LOG_FILE" || {
      log_error "Failed to wipe filesystem signatures"
    }
  fi
  
  # Delete the partition from the partition table using parted
  if command -v parted >/dev/null 2>&1; then
    log "Deleting partition $PARTITION_NUM from $DISK_DEVICE"
    if parted -s "$DISK_DEVICE" rm "$PARTITION_NUM" 2>>"$LOG_FILE"; then
      log "Successfully deleted partition $PARTITION_NUM from partition table"
    else
      log_error "Failed to delete partition from partition table (this may be expected if partition is in use)"
    fi
  else
    log "parted command not found, skipping partition table deletion"
  fi
else
  log_error "Could not determine disk device or partition number from $CONTENT_PARTITION"
fi

log "Content extraction completed successfully"
log "Content files in $CONTENT_DEST:"
ls -lh "$CONTENT_DEST" >> "$LOG_FILE" 2>&1 || true

exit 0

