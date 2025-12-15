#!/bin/bash
set -euo pipefail

# Script to extract content and SPC from COS_CONTENT partition
# This script is called from 80_stylus_maas.yaml during the network stage
# Note: local-ui is handled directly in the iso-image build, not via content partition

# Log file path
LOG_FILE="/var/log/stylus-maas-content-script.log"

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

# Process organized folders from content partition
log "Processing organized folders from content partition..."

# Initialize counters
BUNDLE_COUNT=0
SPC_COUNT=0
USER_DATA_COUNT=0
EDGE_CONFIG_COUNT=0

# Helper function to mount and copy to OEM partition
copy_to_oem() {
  local source_file="$1"
  local dest_filename="$2"
  local description="$3"
  
  OEM_PARTITION=$(blkid -L COS_OEM 2>/dev/null || true)
  if [ -z "$OEM_PARTITION" ]; then
    log_error "COS_OEM partition not found, cannot copy $description"
    return 1
  fi
  
  OEM_MOUNT="/mnt/oem_temp"
  mkdir -p "$OEM_MOUNT"
  if ! mount -o rw "$OEM_PARTITION" "$OEM_MOUNT" 2>>"$LOG_FILE"; then
    log_error "Failed to mount COS_OEM partition to copy $description"
    rmdir "$OEM_MOUNT" 2>>"$LOG_FILE" || true
    return 1
  fi
  
  if cp "$source_file" "$OEM_MOUNT/$dest_filename" 2>>"$LOG_FILE"; then
    log "Successfully copied $description to /oem/$dest_filename"
    umount "$OEM_MOUNT" 2>>"$LOG_FILE" || true
    rmdir "$OEM_MOUNT" 2>>"$LOG_FILE" || true
    return 0
  else
    log_error "Failed to copy $description to /oem/$dest_filename"
    umount "$OEM_MOUNT" 2>>"$LOG_FILE" || true
    rmdir "$OEM_MOUNT" 2>>"$LOG_FILE" || true
    return 1
  fi
}

# Process bundle-content folder: extract .zst and .tar files
BUNDLE_CONTENT_DIR="$CONTENT_MOUNT/bundle-content"
if [ -d "$BUNDLE_CONTENT_DIR" ]; then
  log "Processing bundle-content folder..."
  for file in "$BUNDLE_CONTENT_DIR"/*; do
    if [ -f "$file" ]; then
      FILENAME=$(basename "$file")
      EXTENSION="${FILENAME##*.}"
      
      # Handle .zst files - extract them to bundle directory
      if [ "$EXTENSION" = "zst" ]; then
        log "Extracting .zst file: $FILENAME"
        if zstd -d -f "$file" -o "$CONTENT_DEST/${FILENAME%.zst}" 2>>"$LOG_FILE"; then
          log "Successfully extracted $FILENAME"
          BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
        else
          log_error "Failed to extract $FILENAME, copying as-is"
          cp "$file" "$CONTENT_DEST/$FILENAME" || {
            log_error "Failed to copy $FILENAME"
          }
        fi
      # Handle .tar files - extract them to bundle directory
      elif [ "$EXTENSION" = "tar" ]; then
        log "Extracting .tar file: $FILENAME"
        if tar -xf "$file" -C "$CONTENT_DEST" 2>>"$LOG_FILE"; then
          log "Successfully extracted $FILENAME"
          BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
        else
          log_error "Failed to extract $FILENAME, copying as-is"
          cp "$file" "$CONTENT_DEST/$FILENAME" || {
            log_error "Failed to copy $FILENAME"
          }
        fi
      else
        log "Skipping file with unknown extension in bundle-content: $FILENAME (extension: $EXTENSION)"
      fi
    fi
  done
  log "Processed $BUNDLE_COUNT file(s) from bundle-content folder"
fi

# Process spc-config folder: copy .tgz files directly
SPC_CONFIG_DIR="$CONTENT_MOUNT/spc-config"
if [ -d "$SPC_CONFIG_DIR" ]; then
  log "Processing spc-config folder..."
  for file in "$SPC_CONFIG_DIR"/*; do
    if [ -f "$file" ]; then
      FILENAME=$(basename "$file")
      log "Copying SPC file: $FILENAME"
      if cp "$file" "$CLUSTER_CONFIG_COPY_DIR/$FILENAME" 2>>"$LOG_FILE"; then
        log "Successfully copied SPC file to $CLUSTER_CONFIG_COPY_DIR/$FILENAME"
        SPC_COUNT=$((SPC_COUNT + 1))
      else
        log_error "Failed to copy SPC file: $FILENAME"
      fi
    fi
  done
  log "Processed $SPC_COUNT file(s) from spc-config folder"
fi

# Process userdata folder: copy user-data to /oem/config.yaml
USERDATA_DIR="$CONTENT_MOUNT/userdata"
if [ -d "$USERDATA_DIR" ]; then
  log "Processing userdata folder..."
  USER_DATA_FILE="$USERDATA_DIR/user-data"
  if [ -f "$USER_DATA_FILE" ]; then
    if copy_to_oem "$USER_DATA_FILE" "config.yaml" "user-data"; then
      USER_DATA_COUNT=$((USER_DATA_COUNT + 1))
    fi
  else
    log "No user-data file found in userdata folder"
  fi
fi

# Process edge-config folder: copy EDGE_CUSTOM_CONFIG to /oem/.edge_custom_config.yaml
EDGE_CONFIG_DIR="$CONTENT_MOUNT/edge-config"
if [ -d "$EDGE_CONFIG_DIR" ]; then
  log "Processing edge-config folder..."
  EDGE_CONFIG_FILE="$EDGE_CONFIG_DIR/.edge_custom_config.yaml"
  if [ -f "$EDGE_CONFIG_FILE" ]; then
    if copy_to_oem "$EDGE_CONFIG_FILE" ".edge_custom_config.yaml" "EDGE_CUSTOM_CONFIG"; then
      EDGE_CONFIG_COUNT=$((EDGE_CONFIG_COUNT + 1))
    fi
  else
    log "No .edge_custom_config.yaml file found in edge-config folder"
  fi
fi

log "Extraction summary: $BUNDLE_COUNT bundle file(s) extracted, $SPC_COUNT SPC file(s) copied, $USER_DATA_COUNT user-data file(s), $EDGE_CONFIG_COUNT EDGE_CUSTOM_CONFIG file(s)"

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

