#!/bin/bash
set -euo pipefail

# Script to extract content and SPC from COS_CONTENT partition
# This script is called from 80_stylus_maas.yaml during the network stage
# Note: local-ui is handled directly in the iso-image build, not via content partition

# Find the partition with COS_CONTENT label
CONTENT_PARTITION=$(blkid -L COS_CONTENT 2>/dev/null || true)
if [ -z "$CONTENT_PARTITION" ]; then
  echo "No content partition found with label COS_CONTENT, skipping content extraction"
  exit 0
fi

echo "Found content partition: $CONTENT_PARTITION"

# Create mount point
CONTENT_MOUNT="/mnt/content"
mkdir -p "$CONTENT_MOUNT"

# Mount the content partition
mount -t ext4 "$CONTENT_PARTITION" "$CONTENT_MOUNT" || {
  echo "Error: Failed to mount content partition" >&2
  exit 1
}

# Create destination directories
CONTENT_DEST="/usr/local/spectrocloud/bundle"
mkdir -p "$CONTENT_DEST"
mkdir -p "/opt/spectrocloud/clusterconfig"

# Extract .zst and .tar files from partition
echo "Extracting files from content partition..."

# Process .zst files - extract them to bundle directory
for file in "$CONTENT_MOUNT"/*.zst; do
  if [ -f "$file" ]; then
    FILENAME=$(basename "$file")
    # Skip spc.tgz - it's handled separately
    if [ "$FILENAME" != "spc.tgz" ]; then
      echo "Extracting .zst file: $FILENAME"
      zstd -d -f "$file" -o "$CONTENT_DEST/${FILENAME%.zst}" || {
        echo "Warning: Failed to extract $FILENAME, copying as-is"
        cp "$file" "$CONTENT_DEST/$FILENAME"
      }
    fi
  fi
done

# Process .tar files - extract them
for file in "$CONTENT_MOUNT"/*.tar; do
  if [ -f "$file" ]; then
    FILENAME=$(basename "$file")
    if [ "$FILENAME" = "spc.tgz" ]; then
      # Copy SPC file to clusterconfig directory
      echo "Copying SPC file: $FILENAME"
      cp "$file" "/opt/spectrocloud/clusterconfig/spc.tgz"
    else
      # Other .tar files go to bundle directory
      echo "Extracting .tar file: $FILENAME"
      tar -xf "$file" -C "$CONTENT_DEST" || {
        echo "Warning: Failed to extract $FILENAME, copying as-is"
        cp "$file" "$CONTENT_DEST/$FILENAME"
      }
    fi
  fi
done

# Unmount the content partition
umount "$CONTENT_MOUNT" || true
rmdir "$CONTENT_MOUNT" || true

echo "Content extraction completed"
echo "Content files in $CONTENT_DEST:"
ls -lh "$CONTENT_DEST" || true

exit 0

