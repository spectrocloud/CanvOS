#!/bin/bash -x
#
# This script adds a COS_CONTENT partition to a Kairos raw disk image
# created by auroraboot. The partition will contain content, SPC,
# and edge-config files organized in folders.
#
# This script follows the MAAS approach: it creates a new image from scratch
# with computed partition sizes instead of resizing the existing image.
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
CONTENT_DIR=""
echo "=== Searching for content directories ==="
for base_dir in "$ORIG_DIR" "/workdir" "."; do
    echo "Checking base directory: $base_dir"
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
for tool in losetup qemu-img parted kpartx mkfs.ext4 mkfs.ext2 mkfs.vfat rsync blkid numfmt; do
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

# --- Get original partition sizes and start points ---
echo "--- Analyzing input image partitions... ---"
INPUT_PARTS_INFO=$(parted -s "$INPUT_IMG" unit B print)
echo "Input image partition table:"
echo "$INPUT_PARTS_INFO"
echo ""

# Get input image size for reference
INPUT_IMG_SIZE=$(du -h "$INPUT_IMG" | cut -f1)
echo "Input Kairos raw image size: $INPUT_IMG_SIZE"
echo ""

# Extract partition sizes based on names found in parted output (efi, oem, recovery)
COS_GRUB_START=$(echo "$INPUT_PARTS_INFO" | grep "efi" | awk '{print $2}' | tr -d 'B')
COS_GRUB_SIZE=$(echo "$INPUT_PARTS_INFO" | grep "efi" | awk '{print $4}' | tr -d 'B')
COS_OEM_START=$(echo "$INPUT_PARTS_INFO" | grep "oem" | awk '{print $2}' | tr -d 'B')
COS_OEM_SIZE=$(echo "$INPUT_PARTS_INFO" | grep "oem" | awk '{print $4}' | tr -d 'B')
COS_RECOVERY_START=$(echo "$INPUT_PARTS_INFO" | grep "recovery" | awk '{print $2}' | tr -d 'B')
COS_RECOVERY_SIZE=$(echo "$INPUT_PARTS_INFO" | grep "recovery" | awk '{print $4}' | tr -d 'B')

# Display partition sizes in human-readable format
echo "Partition sizes:"
echo "  EFI (COS_GRUB): $(numfmt --to=iec $COS_GRUB_SIZE) ($COS_GRUB_SIZE bytes)"
echo "  OEM: $(numfmt --to=iec $COS_OEM_SIZE) ($COS_OEM_SIZE bytes)"
echo "  Recovery: $(numfmt --to=iec $COS_RECOVERY_SIZE) ($COS_RECOVERY_SIZE bytes)"
echo ""

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

# Calculate sizes for state and persistent partitions
# These are pre-created to prevent Kairos from overwriting the content partition
# State partition needs to be large enough for active.img and reset operations
# active.img is a copy of the recovery image, so state partition must be >= recovery partition size
# Add 20% overhead for filesystem metadata and safety margin
MIN_STATE_SIZE_BYTES=$((4 * 1024 * 1024 * 1024))  # Minimum 4GB
STATE_SIZE_BYTES=$(($COS_RECOVERY_SIZE + $COS_RECOVERY_SIZE / 5))  # Recovery size + 20% overhead
# Ensure state partition is at least 4GB (for smaller recovery images)
if [ "$STATE_SIZE_BYTES" -lt "$MIN_STATE_SIZE_BYTES" ]; then
    STATE_SIZE_BYTES=$MIN_STATE_SIZE_BYTES
fi
PERSISTENT_SIZE_BYTES=$((2 * 1024 * 1024 * 1024))  # 2GB

# Calculate final image size: sum of all partitions + 1MB overhead
# Include state and persistent partitions to prevent Kairos from creating them and overwriting content
FINAL_IMG_SIZE_BYTES=$(($COS_GRUB_SIZE + $COS_OEM_SIZE + $COS_RECOVERY_SIZE + $STATE_SIZE_BYTES + $PERSISTENT_SIZE_BYTES + $CONTENT_SIZE_BYTES + 1024*1024))
FINAL_IMG_SIZE=$(numfmt --to=iec "$FINAL_IMG_SIZE_BYTES")

# --- Partition & sizing ---
echo "--- Creating and Partitioning Final Image ---"
echo "Partition sizes:"
echo "  EFI (COS_GRUB): $(numfmt --to=iec $COS_GRUB_SIZE)"
echo "  OEM: $(numfmt --to=iec $COS_OEM_SIZE)"
echo "  Recovery: $(numfmt --to=iec $COS_RECOVERY_SIZE)"
echo "  State: $(numfmt --to=iec $STATE_SIZE_BYTES) (calculated from recovery size + 20% overhead, min 4GB, pre-created to prevent Kairos from overwriting content)"
echo "  Persistent: $(numfmt --to=iec $PERSISTENT_SIZE_BYTES) (pre-created to prevent Kairos from overwriting content)"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    echo "  Content: $(numfmt --to=iec $CONTENT_SIZE_BYTES)"
fi
echo ""

FINAL_IMG="$WORKDIR/kairos.raw"
qemu-img create -f raw "$FINAL_IMG" "$FINAL_IMG_SIZE"

# Partition offsets (in MiB for parted)
COS_GRUB_END_BYTES=$(($COS_GRUB_SIZE / 1024 / 1024))
COS_GRUB_END="${COS_GRUB_END_BYTES}MiB"
COS_OEM_END_BYTES=$(($COS_GRUB_END_BYTES + $COS_OEM_SIZE / 1024 / 1024))
COS_OEM_END="${COS_OEM_END_BYTES}MiB"
# Calculate the fixed end point for the recovery partition
COS_RECOVERY_END_BYTES=$(($COS_OEM_END_BYTES + $COS_RECOVERY_SIZE / 1024 / 1024))
COS_RECOVERY_END="${COS_RECOVERY_END_BYTES}MiB"

# Calculate state partition end point
STATE_END_BYTES=$(($COS_RECOVERY_END_BYTES + $STATE_SIZE_BYTES / 1024 / 1024))
STATE_END="${STATE_END_BYTES}MiB"

# Calculate persistent partition end point
PERSISTENT_END_BYTES=$(($STATE_END_BYTES + $PERSISTENT_SIZE_BYTES / 1024 / 1024))
PERSISTENT_END="${PERSISTENT_END_BYTES}MiB"

# Calculate content partition end point (if content exists)
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    CONTENT_END_BYTES=$(($PERSISTENT_END_BYTES + $CONTENT_SIZE_BYTES / 1024 / 1024))
    CONTENT_END="${CONTENT_END_BYTES}MiB"
else
    CONTENT_END="$PERSISTENT_END"
fi

# Create partitions with names that match the source image
# IMPORTANT: We create state and persistent partitions BEFORE content partition
# to prevent Kairos from overwriting the content partition during boot
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    echo "Creating partitions: efi, oem, recovery, state, persistent, content"
    parted -s "$FINAL_IMG" -- \
      mklabel gpt \
      mkpart efi fat32 1MiB "$COS_GRUB_END" \
      set 1 esp on \
      mkpart oem ext2 "$COS_GRUB_END" "$COS_OEM_END" \
      mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END" \
      mkpart state ext2 "$COS_RECOVERY_END" "$STATE_END" \
      mkpart persistent ext2 "$STATE_END" "$PERSISTENT_END" \
      mkpart content ext4 "$PERSISTENT_END" "$CONTENT_END" \
      name 4 state \
      name 5 persistent \
      name 6 COS_CONTENT \
      set 6 msftdata off || {
        echo "Error: Failed to create partitions" >&2
        exit 1
    }
    # Set partition type GUIDs to ensure they're recognized
    if command -v sgdisk >/dev/null 2>&1; then
        echo "Setting partition type GUIDs..."
        sgdisk -t 4:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for state"
        sgdisk -t 5:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for persistent"
        sgdisk -t 6:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for content"
    fi
    echo "Partitions created successfully"
    echo "Final partition table:"
    parted -s "$FINAL_IMG" print
else
    # Even without content, create state and persistent to match expected layout
    echo "Creating partitions: efi, oem, recovery, state, persistent"
    parted -s "$FINAL_IMG" -- \
      mklabel gpt \
      mkpart efi fat32 1MiB "$COS_GRUB_END" \
      set 1 esp on \
      mkpart oem ext2 "$COS_GRUB_END" "$COS_OEM_END" \
      mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END" \
      mkpart state ext2 "$COS_RECOVERY_END" "$STATE_END" \
      mkpart persistent ext2 "$STATE_END" "$PERSISTENT_END" \
      name 4 state \
      name 5 persistent || {
        echo "Error: Failed to create partitions" >&2
        exit 1
    }
    if command -v sgdisk >/dev/null 2>&1; then
        sgdisk -t 4:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for state"
        sgdisk -t 5:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for persistent"
    fi
fi

# --- Loop setup for device mapping ---
echo "--- Setting up loop devices ---"
INPUT_PARTS=($(kpartx -avs "$INPUT_IMG" | awk '{print "/dev/mapper/" $3}'))
# Use the correct index from kpartx output based on partition order
INPUT_EFI_DEV="${INPUT_PARTS[0]}"
INPUT_OEM_DEV="${INPUT_PARTS[1]}"
INPUT_RECOVERY_DEV="${INPUT_PARTS[2]}"

FINAL_PARTS=($(kpartx -avs "$FINAL_IMG" | awk '{print "/dev/mapper/" $3}'))
FINAL_EFI_DEV="${FINAL_PARTS[0]}"
FINAL_OEM_DEV="${FINAL_PARTS[1]}"
FINAL_RECOVERY_DEV="${FINAL_PARTS[2]}"
FINAL_STATE_DEV="${FINAL_PARTS[3]}"
FINAL_PERSISTENT_DEV="${FINAL_PARTS[4]}"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    FINAL_CONTENT_DEV="${FINAL_PARTS[5]}"
fi

sleep 2

# --- Format and Mount Filesystems ---
echo "--- Formatting and Mounting Partitions ---"
# Use mkfs to apply the desired labels to the newly created partitions
mkfs.vfat -n "COS_GRUB" "$FINAL_EFI_DEV"
mkfs.ext2 -L COS_OEM "$FINAL_OEM_DEV"
mkfs.ext2 -L COS_RECOVERY "$FINAL_RECOVERY_DEV"
# Format state and persistent partitions with appropriate labels
# These are pre-created so Kairos won't overwrite the content partition
mkfs.ext2 -L COS_STATE "$FINAL_STATE_DEV"
mkfs.ext2 -L COS_PERSISTENT "$FINAL_PERSISTENT_DEV"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    mkfs.ext4 -L COS_CONTENT "$FINAL_CONTENT_DEV"
fi

MNT_INPUT_EFI=$(mktemp -d)
MNT_INPUT_OEM=$(mktemp -d)
MNT_INPUT_RECOVERY=$(mktemp -d)

MNT_FINAL_EFI=$(mktemp -d)
MNT_FINAL_OEM=$(mktemp -d)
MNT_FINAL_RECOVERY=$(mktemp -d)
MNT_FINAL_STATE=$(mktemp -d)
MNT_FINAL_PERSISTENT=$(mktemp -d)
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    MNT_FINAL_CONTENT=$(mktemp -d)
fi

mount -t vfat "$INPUT_EFI_DEV" "$MNT_INPUT_EFI"
mount -t ext2 "$INPUT_OEM_DEV" "$MNT_INPUT_OEM"
mount -t ext2 "$INPUT_RECOVERY_DEV" "$MNT_INPUT_RECOVERY"

mount -t vfat "$FINAL_EFI_DEV" "$MNT_FINAL_EFI"
mount -t ext2 "$FINAL_OEM_DEV" "$MNT_FINAL_OEM"
mount -t ext2 "$FINAL_RECOVERY_DEV" "$MNT_FINAL_RECOVERY"
# Note: We don't mount state and persistent here - they'll be used by Kairos during boot
# We just created them to prevent Kairos from overwriting the content partition
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    mount "$FINAL_CONTENT_DEV" "$MNT_FINAL_CONTENT"
fi

# --- Copy Filesystems ---
echo "--- Copying Filesystem Data ---"
echo "Copying EFI partition..."
rsync -aHAX --info=progress2 "$MNT_INPUT_EFI/" "$MNT_FINAL_EFI/" || { echo "Error: Failed to copy EFI partition"; exit 1; }
echo "Copying OEM partition..."
rsync -aHAX --info=progress2 "$MNT_INPUT_OEM/" "$MNT_FINAL_OEM/" || { echo "Error: Failed to copy OEM partition"; exit 1; }
echo "Copying Recovery partition (size: $(numfmt --to=iec $COS_RECOVERY_SIZE))..."
rsync -aHAX --info=progress2 "$MNT_INPUT_RECOVERY/" "$MNT_FINAL_RECOVERY/" || { echo "Error: Failed to copy Recovery partition"; exit 1; }

# Verify recovery partition was copied correctly
echo "Verifying recovery partition copy..."
RECOVERY_IN_SIZE=$(du -sb "$MNT_INPUT_RECOVERY" 2>/dev/null | cut -f1 || echo "0")
RECOVERY_OUT_SIZE=$(du -sb "$MNT_FINAL_RECOVERY" 2>/dev/null | cut -f1 || echo "0")
echo "  Input recovery size: $(numfmt --to=iec $RECOVERY_IN_SIZE)"
echo "  Output recovery size: $(numfmt --to=iec $RECOVERY_OUT_SIZE)"

# Copy content files and SPC to content partition if it exists
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    echo "--- Copying Files to Content Partition (Organized by Folders) ---"
    mkdir -p "$MNT_FINAL_CONTENT"
    
    # Create organized folder structure
    mkdir -p "$MNT_FINAL_CONTENT/bundle-content"
    mkdir -p "$MNT_FINAL_CONTENT/spc-config"
    mkdir -p "$MNT_FINAL_CONTENT/edge-config"
    
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
    
    # Copy SPC file if it exists to spc-config folder (preserve original filename)
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
fi

# Sync filesystem
echo "Syncing filesystem..."
sync

# --- Finalize ---
echo "--- Unmounting and cleaning up ---"
umount -l "$MNT_INPUT_EFI" || true
umount -l "$MNT_INPUT_OEM" || true
umount -l "$MNT_INPUT_RECOVERY" || true
umount -l "$MNT_FINAL_EFI" || true
umount -l "$MNT_FINAL_OEM" || true
umount -l "$MNT_FINAL_RECOVERY" || true
# Note: state and persistent are not mounted, so no need to unmount
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    umount -l "$MNT_FINAL_CONTENT" || true
fi

kpartx -d "$FINAL_IMG" || true
kpartx -d "$INPUT_IMG" || true

echo "--- Copying final image back to original location... ---"
cp "$FINAL_IMG" "$INPUT_IMG"

# Verify partition table before finalizing
echo "--- Verifying final partition table ---"
parted -s "$INPUT_IMG" print
echo ""
echo "Checking for all partitions:"
# Use kpartx to check partitions
kpartx -avs "$INPUT_IMG" 2>&1 | head -20
echo ""
echo "Checking partition labels:"
# Try blkid on the image file
if command -v blkid >/dev/null 2>&1; then
    echo "Partition labels found:"
    blkid "$INPUT_IMG"* 2>/dev/null | grep -E "COS_|state|persistent" || echo "Partition labels not found in blkid (may need to be mounted)"
    echo ""
    echo "Checking for COS_CONTENT partition:"
    blkid "$INPUT_IMG"* 2>/dev/null | grep -i "COS_CONTENT" || echo "COS_CONTENT not found in blkid (may need to be mounted)"
    echo ""
    echo "Checking for COS_STATE partition:"
    blkid "$INPUT_IMG"* 2>/dev/null | grep -i "COS_STATE" || echo "COS_STATE not found in blkid (may need to be mounted)"
    echo ""
    echo "Checking for COS_PERSISTENT partition:"
    blkid "$INPUT_IMG"* 2>/dev/null | grep -i "COS_PERSISTENT" || echo "COS_PERSISTENT not found in blkid (may need to be mounted)"
fi
echo ""

# Report final image information
FINAL_IMG_SIZE=$(du -h "$INPUT_IMG" | cut -f1)
echo "Final image with content partition: $INPUT_IMG"
echo "Final image size: $FINAL_IMG_SIZE"
echo "Expected size: ~$(numfmt --to=iec $FINAL_IMG_SIZE_BYTES)"
echo ""

# Cleanup
rm -rf "$MNT_INPUT_EFI" "$MNT_INPUT_OEM" "$MNT_INPUT_RECOVERY" "$MNT_FINAL_EFI" "$MNT_FINAL_OEM" "$MNT_FINAL_RECOVERY" "$MNT_FINAL_STATE" "$MNT_FINAL_PERSISTENT"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    rm -rf "$MNT_FINAL_CONTENT"
fi
rm -rf "$WORKDIR"
CLEANUP_DONE=true

echo "✅ Content partition added successfully to image"

exit 0
