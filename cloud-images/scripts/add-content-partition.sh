#!/bin/bash -x
#
# This script adds a COS_CONTENT partition to a Kairos raw disk image
# created by auroraboot. The partition will contain content, SPC,
# and edge-config files organized in folders.
#
set -euo pipefail

# --- Configuration ---
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <path_to_kairos_raw_image> [content_size]" >&2
    echo "  content_size: Optional size for content partition (e.g., 2G, 5G)" >&2
    echo "               Default: calculated based on actual content size" >&2
    exit 1
fi

# Convert the input path to an absolute path
# Use realpath if available, otherwise fall back to readlink or just use the path as-is
if command -v realpath >/dev/null 2>&1; then
    INPUT_IMG=$(realpath "$1")
elif command -v readlink >/dev/null 2>&1; then
    INPUT_IMG=$(readlink -f "$1" 2>/dev/null || echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")")
else
    INPUT_IMG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi

# Verify the input image exists
if [ ! -f "$INPUT_IMG" ]; then
    echo "Error: Input image file not found: $INPUT_IMG" >&2
    echo "Current directory: $(pwd)" >&2
    echo "Original path provided: $1" >&2
    exit 1
fi

ORIG_DIR=$(pwd)
echo "Working from directory: $ORIG_DIR"
echo "Input image: $INPUT_IMG"

# Default content partition size (will be calculated if content files exist)
CONTENT_SIZE="${2:-2G}"

# Path to content directory (if content files are provided)
# Look for content-* directories in multiple locations
CONTENT_DIR=""
echo "=== Searching for content directories ==="
# Check multiple possible locations
for base_dir in "$ORIG_DIR" "/workdir" "."; do
    echo "Checking base directory: $base_dir"
    # Check for content-* directories (use shopt to handle glob failures)
    shopt -s nullglob
    for dir in "$base_dir"/content-*; do
        if [ -d "$dir" ]; then
            CONTENT_DIR="$dir"
            echo "Found content directory: $CONTENT_DIR"
            shopt -u nullglob
            break 2
        fi
    done
    shopt -u nullglob
    # Check for plain content directory
    if [ -d "$base_dir/content" ]; then
        CONTENT_DIR="$base_dir/content"
        echo "Found content directory: $CONTENT_DIR"
        break
    fi
done

# If no content directory found, check for files directly in base directories
if [ -z "$CONTENT_DIR" ]; then
    echo "No content-* directories found, checking for files directly in base directories..."
    for base_dir in "/workdir" "$ORIG_DIR" "."; do
        if [ -d "$base_dir" ]; then
            FILE_COUNT=$(find "$base_dir" -maxdepth 1 -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | wc -l)
            if [ "$FILE_COUNT" -gt 0 ]; then
                echo "Found $FILE_COUNT content file(s) directly in $base_dir"
                CONTENT_DIR="$base_dir"
                break
            fi
        fi
    done
fi

if [ -z "$CONTENT_DIR" ]; then
    echo "No content directory or files found"
else
    echo "Using content directory: $CONTENT_DIR"
fi

# Path to cluster config (SPC) file if provided
CLUSTERCONFIG_FILE=""
if [ -n "${CLUSTERCONFIG:-}" ] && [ -f "${CLUSTERCONFIG}" ]; then
    CLUSTERCONFIG_FILE="${CLUSTERCONFIG}"
elif [ -f "$ORIG_DIR/spc.tgz" ]; then
    CLUSTERCONFIG_FILE="$ORIG_DIR/spc.tgz"
elif [ -f "./spc.tgz" ]; then
    CLUSTERCONFIG_FILE="./spc.tgz"
elif [ -f "/workdir/spc.tgz" ]; then
    CLUSTERCONFIG_FILE="/workdir/spc.tgz"
fi

# Path to EDGE_CUSTOM_CONFIG file if provided
EDGE_CUSTOM_CONFIG_FILE=""
if [ -n "${EDGE_CUSTOM_CONFIG:-}" ] && [ -f "${EDGE_CUSTOM_CONFIG}" ]; then
    EDGE_CUSTOM_CONFIG_FILE="${EDGE_CUSTOM_CONFIG}"
    echo "EDGE_CUSTOM_CONFIG file found: $EDGE_CUSTOM_CONFIG_FILE"
elif [ -f "$ORIG_DIR/edge_custom_config.yaml" ]; then
    EDGE_CUSTOM_CONFIG_FILE="$ORIG_DIR/edge_custom_config.yaml"
    echo "EDGE_CUSTOM_CONFIG file found: $EDGE_CUSTOM_CONFIG_FILE"
elif [ -f "./edge_custom_config.yaml" ]; then
    EDGE_CUSTOM_CONFIG_FILE="./edge_custom_config.yaml"
    echo "EDGE_CUSTOM_CONFIG file found: $EDGE_CUSTOM_CONFIG_FILE"
elif [ -f "/workdir/edge_custom_config.yaml" ]; then
    EDGE_CUSTOM_CONFIG_FILE="/workdir/edge_custom_config.yaml"
    echo "EDGE_CUSTOM_CONFIG file found: $EDGE_CUSTOM_CONFIG_FILE"
fi

# Note: local-ui is handled directly in the iso-image build, not via content partition
# So we don't need to look for or copy local-ui.tar here

# --- Tools check ---
for tool in losetup qemu-img parted kpartx mkfs.ext4 rsync blkid; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: Required tool '$tool' is not installed." >&2
        exit 1
    fi
done

# --- Temp workspace ---
WORKDIR=$(mktemp -d)
CLEANUP_DONE=false
trap 'EXIT_CODE=$?; \
      if [ "$CLEANUP_DONE" = "false" ]; then \
          echo "Cleaning up..."; \
          umount -l "$WORKDIR"/* &>/dev/null || true; \
          if [ -n "$FINAL_IMG" ]; then kpartx -d "$FINAL_IMG" &>/dev/null || true; fi; \
          if [ -n "$INPUT_IMG" ]; then kpartx -d "$INPUT_IMG" &>/dev/null || true; fi; \
          rm -rf "$WORKDIR" || true; \
          CLEANUP_DONE=true; \
      fi; \
      exit $EXIT_CODE' EXIT
cd "$WORKDIR"

# Copy input image to work directory
cp "$INPUT_IMG" kairos.raw || {
    echo "Error: Failed to copy input image to work directory" >&2
    exit 1
}
FINAL_IMG="$WORKDIR/kairos.raw"

# --- Analyze existing partitions ---
echo "--- Analyzing existing image partitions... ---"
INPUT_PARTS_INFO=$(parted -s "$FINAL_IMG" unit B print)
echo "Input image partition table:"
echo "$INPUT_PARTS_INFO"
echo ""

# Get the last partition end position
LAST_PART_END=$(echo "$INPUT_PARTS_INFO" | grep -E "^[[:space:]]*[0-9]+" | tail -1 | awk '{print $3}' | tr -d 'B')
if [ -z "$LAST_PART_END" ]; then
    echo "Error: Could not determine last partition end position" >&2
    echo "Partition info:"
    echo "$INPUT_PARTS_INFO"
    exit 1
fi
LAST_PART_END_MB=$(($LAST_PART_END / 1024 / 1024))
echo "Last partition ends at: ${LAST_PART_END_MB}MiB"

# Calculate size needed for content partition
CONTENT_SIZE_BYTES=0
HAS_CONTENT=false
CONTENT_FILES_SIZE=0

# Calculate size of content files
echo "=== Calculating content files size ==="
echo "CONTENT_DIR is currently: ${CONTENT_DIR:-'(empty)'}"

# First check content-* directories
if [ -n "$CONTENT_DIR" ] && [ -d "$CONTENT_DIR" ]; then
    FILE_COUNT=$(find "$CONTENT_DIR" -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        CONTENT_FILES_SIZE=$(find "$CONTENT_DIR" -type f \( -name "*.zst" -o -name "*.tar" \) -exec du -cb {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
        echo "Found $FILE_COUNT content file(s) in directory: $CONTENT_DIR (size: $(numfmt --to=iec $CONTENT_FILES_SIZE 2>/dev/null || echo $CONTENT_FILES_SIZE))"
    else
        echo "No content files found in $CONTENT_DIR"
        CONTENT_DIR=""
    fi
fi

# Also check for .zst and .tar files directly in /workdir if no content directory was found or no files in it
if [ "$CONTENT_FILES_SIZE" -eq 0 ] || [ -z "$CONTENT_DIR" ]; then
    echo "Checking for files directly in base directories..."
    for base_dir in "/workdir" "$ORIG_DIR" "."; do
        if [ -d "$base_dir" ]; then
            FILE_COUNT=$(find "$base_dir" -maxdepth 1 -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | wc -l)
            if [ "$FILE_COUNT" -gt 0 ]; then
                CONTENT_FILES_SIZE=$(find "$base_dir" -maxdepth 1 -type f \( -name "*.zst" -o -name "*.tar" \) -exec du -cb {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
                if [ "$CONTENT_FILES_SIZE" -gt 0 ]; then
                    CONTENT_DIR="$base_dir"
                    echo "Found $FILE_COUNT content file(s) directly in: $CONTENT_DIR (size: $(numfmt --to=iec $CONTENT_FILES_SIZE 2>/dev/null || echo $CONTENT_FILES_SIZE))"
                    break
                fi
            fi
        fi
    done
fi

# Add size of SPC file if it exists
if [ -n "$CLUSTERCONFIG_FILE" ] && [ -f "$CLUSTERCONFIG_FILE" ]; then
    SPC_SIZE=$(du -cb "$CLUSTERCONFIG_FILE" 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
    CONTENT_FILES_SIZE=$(($CONTENT_FILES_SIZE + $SPC_SIZE))
fi

# Add size of EDGE_CUSTOM_CONFIG file if it exists
if [ -n "$EDGE_CUSTOM_CONFIG_FILE" ] && [ -f "$EDGE_CUSTOM_CONFIG_FILE" ]; then
    EDGE_CUSTOM_CONFIG_SIZE=$(du -cb "$EDGE_CUSTOM_CONFIG_FILE" 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
    CONTENT_FILES_SIZE=$(($CONTENT_FILES_SIZE + $EDGE_CUSTOM_CONFIG_SIZE))
fi

# Note: local-ui is handled directly in the iso-image build, not via content partition
# So we don't need to add its size to CONTENT_FILES_SIZE

# Create content partition if we have any files to store
if [ "$CONTENT_FILES_SIZE" -gt 0 ]; then
    HAS_CONTENT=true
    # Add 20% overhead for filesystem metadata and safety margin
    CONTENT_SIZE_BYTES=$(($CONTENT_FILES_SIZE + $CONTENT_FILES_SIZE / 5 + 100*1024*1024))
    CONTENT_SIZE=$(numfmt --to=iec "$CONTENT_SIZE_BYTES")
    echo "Content files found: $(numfmt --to=iec $CONTENT_FILES_SIZE)"
    echo "Content partition size: $CONTENT_SIZE (with overhead)"
else
    echo "No content files found, skipping content partition"
    exit 0
fi
echo ""

# Resize the image to accommodate the new partition
CONTENT_SIZE_BYTES=$(numfmt --from=iec "$CONTENT_SIZE")
# Add extra space for GPT overhead (typically 34 sectors = 17KB, but we'll add 2MB buffer)
NEW_IMG_SIZE_BYTES=$(($LAST_PART_END + $CONTENT_SIZE_BYTES + 2*1024*1024))
NEW_IMG_SIZE=$(numfmt --to=iec "$NEW_IMG_SIZE_BYTES")
echo "Resizing image from $(numfmt --to=iec $LAST_PART_END) to $NEW_IMG_SIZE"
qemu-img resize -f raw "$FINAL_IMG" "$NEW_IMG_SIZE" || {
    echo "Error: Failed to resize image" >&2
    exit 1
}

# Fix GPT to recognize the new disk size (this is critical after resize)
echo "Fixing GPT to recognize new disk size..."
# Use sgdisk to expand GPT if available, otherwise use parted's fix
if command -v sgdisk &>/dev/null; then
    sgdisk -e "$FINAL_IMG" 2>&1 || echo "Warning: sgdisk -e failed, continuing anyway"
else
    # Try to fix GPT with parted by reading and rewriting partition table
    # This forces parted to recognize the new size
    partprobe "$FINAL_IMG" &>/dev/null || true
    sleep 1
fi

# Get the actual disk size after resize
ACTUAL_DISK_SIZE_BYTES=$(stat -c%s "$FINAL_IMG" 2>/dev/null || echo "0")
if [ "$ACTUAL_DISK_SIZE_BYTES" -eq 0 ]; then
    echo "Error: Could not determine actual disk size after resize" >&2
    exit 1
fi
ACTUAL_DISK_SIZE_MB=$((ACTUAL_DISK_SIZE_BYTES / 1024 / 1024))
echo "Actual disk size after resize: ${ACTUAL_DISK_SIZE_MB}MiB"

# Re-read partition table to get updated last partition end
UPDATED_PARTS_INFO=$(parted -s "$FINAL_IMG" unit B print 2>&1) || {
    echo "Error: Failed to read partition table after resize" >&2
    exit 1
}
UPDATED_LAST_PART_END=$(echo "$UPDATED_PARTS_INFO" | grep -E "^[[:space:]]*[0-9]+" | tail -1 | awk '{print $3}' | tr -d 'B')
if [ -z "$UPDATED_LAST_PART_END" ]; then
    echo "Warning: Could not determine updated last partition end, using original value" >&2
    UPDATED_LAST_PART_END=$LAST_PART_END
fi
UPDATED_LAST_PART_END_MB=$(($UPDATED_LAST_PART_END / 1024 / 1024))
echo "Last partition ends at: ${UPDATED_LAST_PART_END_MB}MiB (after GPT fix)"

# Calculate partition start and end positions
# Start after the last partition with 1MB gap for alignment
CONTENT_START_MB=$((UPDATED_LAST_PART_END_MB + 1))
# Calculate desired end position
DESIRED_END_MB=$((CONTENT_START_MB + CONTENT_SIZE_BYTES / 1024 / 1024))
# But ensure we don't exceed the actual disk size (leave 2MB for GPT and safety)
MAX_END_MB=$((ACTUAL_DISK_SIZE_MB - 2))
CONTENT_END_MB=$((DESIRED_END_MB < MAX_END_MB ? DESIRED_END_MB : MAX_END_MB))

# Ensure we have at least some space for the partition
if [ "$CONTENT_END_MB" -le "$CONTENT_START_MB" ]; then
    echo "Error: Not enough space for content partition. Start: ${CONTENT_START_MB}MiB, End: ${CONTENT_END_MB}MiB, Disk: ${ACTUAL_DISK_SIZE_MB}MiB" >&2
    exit 1
fi

echo "Partition start: ${CONTENT_START_MB}MiB, end: ${CONTENT_END_MB}MiB"

# Create the content partition
echo "--- Creating content partition ---"
# Use unit s (sectors) for more precise control, or use MiB with proper calculation
parted -s "$FINAL_IMG" \
  mkpart content ext4 "${CONTENT_START_MB}MiB" "${CONTENT_END_MB}MiB" || {
    echo "Error: Failed to create content partition" >&2
    echo "Trying to show partition table for debugging:" >&2
    parted -s "$FINAL_IMG" print || true
    exit 1
}

# --- Loop setup for device mapping ---
echo "--- Setting up loop devices ---"
KPARTX_OUTPUT=$(kpartx -avs "$FINAL_IMG" 2>&1)
if [ $? -ne 0 ]; then
    echo "Error: Failed to setup loop devices with kpartx" >&2
    echo "kpartx output: $KPARTX_OUTPUT" >&2
    exit 1
fi
FINAL_PARTS=($(echo "$KPARTX_OUTPUT" | awk '{print "/dev/mapper/" $3}'))
# Get the last partition (use array length instead of [-1] for compatibility)
FINAL_PARTS_COUNT=${#FINAL_PARTS[@]}
if [ "$FINAL_PARTS_COUNT" -eq 0 ]; then
    echo "Error: No partitions found in image" >&2
    echo "kpartx output: $KPARTX_OUTPUT" >&2
    exit 1
fi
FINAL_CONTENT_DEV="${FINAL_PARTS[$((FINAL_PARTS_COUNT - 1))]}"
echo "Content partition device: $FINAL_CONTENT_DEV"
# Verify the device exists
if [ ! -b "$FINAL_CONTENT_DEV" ]; then
    echo "Error: Content partition device does not exist: $FINAL_CONTENT_DEV" >&2
    echo "Available devices:" >&2
    ls -la /dev/mapper/ | grep "$(basename "$FINAL_IMG")" || true
    exit 1
fi

sleep 2

# --- Format and Mount Content Partition ---
echo "--- Formatting and Mounting Content Partition ---"
mkfs.ext4 -L COS_CONTENT "$FINAL_CONTENT_DEV" || {
    echo "Error: Failed to format content partition" >&2
    exit 1
}

MNT_FINAL_CONTENT=$(mktemp -d)
mount "$FINAL_CONTENT_DEV" "$MNT_FINAL_CONTENT" || {
    echo "Error: Failed to mount content partition" >&2
    exit 1
}

# --- Copy Files to Content Partition ---
echo "--- Copying Files to Content Partition (Organized by Folders) ---"
mkdir -p "$MNT_FINAL_CONTENT/bundle-content"
mkdir -p "$MNT_FINAL_CONTENT/spc-config"
mkdir -p "$MNT_FINAL_CONTENT/edge-config"
# Note: local-ui is handled directly in the iso-image build, not via content partition

# Copy all content files (.zst and .tar files only) to bundle-content folder
if [ -d "$CONTENT_DIR" ]; then
    # If CONTENT_DIR is a base directory (like /workdir), only look at files directly in it (maxdepth 1)
    # Otherwise, search recursively in the directory
    if [ "$CONTENT_DIR" = "/workdir" ] || [ "$CONTENT_DIR" = "$ORIG_DIR" ] || [ "$CONTENT_DIR" = "." ]; then
        find "$CONTENT_DIR" -maxdepth 1 -type f \( -name "*.zst" -o -name "*.tar" \) -exec cp -v {} "$MNT_FINAL_CONTENT/bundle-content/" \;
    else
        find "$CONTENT_DIR" -type f \( -name "*.zst" -o -name "*.tar" \) -exec cp -v {} "$MNT_FINAL_CONTENT/bundle-content/" \;
    fi
    BUNDLE_COUNT=$(find "$MNT_FINAL_CONTENT/bundle-content" -type f | wc -l)
    echo "Copied $BUNDLE_COUNT content file(s) to bundle-content folder"
fi

# Copy SPC file if it exists to spc-config folder
if [ -n "$CLUSTERCONFIG_FILE" ] && [ -f "$CLUSTERCONFIG_FILE" ]; then
    SPC_FILENAME=$(basename "$CLUSTERCONFIG_FILE")
    cp -v "$CLUSTERCONFIG_FILE" "$MNT_FINAL_CONTENT/spc-config/$SPC_FILENAME"
    echo "Copied SPC file to spc-config folder: $SPC_FILENAME"
fi

# Copy EDGE_CUSTOM_CONFIG file if it exists to edge-config folder
if [ -n "$EDGE_CUSTOM_CONFIG_FILE" ] && [ -f "$EDGE_CUSTOM_CONFIG_FILE" ]; then
    cp -v "$EDGE_CUSTOM_CONFIG_FILE" "$MNT_FINAL_CONTENT/edge-config/.edge_custom_config.yaml"
    echo "Copied EDGE_CUSTOM_CONFIG file to edge-config folder"
fi

# Note: local-ui is handled directly in the iso-image build, not via content partition
# So we don't copy it here

CONTENT_COUNT=$(find "$MNT_FINAL_CONTENT" -type f | wc -l)
echo "Total files in content partition: $CONTENT_COUNT"
echo "Content partition usage:"
df -h "$MNT_FINAL_CONTENT" || true

# Sync filesystem
echo "Syncing filesystem..."
sync

# --- Finalize ---
echo "--- Verifying final image before unmounting ---"
echo "Final image partition table:"
parted -s "$FINAL_IMG" print
echo ""

echo "Filesystem labels:"
blkid "$FINAL_CONTENT_DEV" 2>/dev/null || true
echo ""

echo "--- Unmounting and cleaning up ---"
umount -l "$MNT_FINAL_CONTENT" || true
kpartx -d "$FINAL_IMG" || true

echo "--- Copying final image back to original location... ---"
cp "$FINAL_IMG" "$INPUT_IMG"

# Report final image information
FINAL_IMG_SIZE=$(du -h "$INPUT_IMG" | cut -f1)
echo "Final image with content partition: $INPUT_IMG"
echo "Final image size: $FINAL_IMG_SIZE"
echo ""

rm -rf "$MNT_FINAL_CONTENT" "$WORKDIR"
CLEANUP_DONE=true

echo "✅ Content partition added successfully to image"

exit 0

