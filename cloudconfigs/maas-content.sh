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
  
  # Use mktemp to create a temporary directory that's guaranteed to exist
  OEM_MOUNT=$(mktemp -d) || {
    log_error "Failed to create temporary mount point directory"
    return 1
  }
  
  if ! mount -o rw "$OEM_PARTITION" "$OEM_MOUNT" 2>>"$LOG_FILE"; then
    log_error "Failed to mount COS_OEM partition ($OEM_PARTITION) to $OEM_MOUNT to copy $description"
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

log "Extraction summary: $BUNDLE_COUNT bundle file(s) extracted, $SPC_COUNT SPC file(s) copied, $EDGE_CONFIG_COUNT EDGE_CUSTOM_CONFIG file(s)"

# Unmount the content partition
log "Unmounting content partition"
umount "$CONTENT_MOUNT" || {
  log_error "Failed to unmount content partition"
  exit 1
}
rmdir "$CONTENT_MOUNT" || true
log "Successfully unmounted content partition"

log "Content extraction completed successfully"
log "Note: Content partition deletion and persistent partition extension will be handled by maas-extend-persistent.sh"
log "Content files in $CONTENT_DEST:"
ls -lh "$CONTENT_DEST" >> "$LOG_FILE" 2>&1 || true

exit 0

