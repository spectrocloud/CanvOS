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
    HAS_CONTENT=false
    CONTENT_SIZE_BYTES=0
fi
echo ""

# Calculate state and persistent partition sizes
# Only create state/persistent when content is present to prevent Kairos from overwriting content partition
# When no content, let Kairos create state/persistent itself
# Based on Kairos documentation: https://kairos.io/docs/reference/configuration/
# Kairos creates partitions sequentially: COS_OEM → COS_RECOVERY → COS_STATE → COS_PERSISTENT
# We pre-create state/persistent with correct labels so Kairos detects and uses them
# This prevents Kairos from overwriting our content partition

if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    # State partition: needs to hold active.img (copy of recovery image) + overhead
    # Minimum 4GB, but use recovery size + 20% overhead for safety
    MIN_STATE_SIZE_BYTES=$((4 * 1024 * 1024 * 1024))  # 4GB minimum
    STATE_SIZE_BYTES=$((COS_RECOVERY_SIZE + COS_RECOVERY_SIZE / 5))  # Recovery size + 20%
    if [ "$STATE_SIZE_BYTES" -lt "$MIN_STATE_SIZE_BYTES" ]; then
        STATE_SIZE_BYTES=$MIN_STATE_SIZE_BYTES
    fi
    
    # Persistent partition: base size + content-based size
    # Persistent needs space for extracted content (can be larger than compressed)
    # Use 100% of content size + 20% overhead
    MIN_PERSISTENT_SIZE_BYTES=$((1 * 1024 * 1024 * 1024))  # 1GB minimum
    CONTENT_BASED_PERSISTENT=$(($CONTENT_SIZE_BYTES + $CONTENT_SIZE_BYTES / 5))
    PERSISTENT_SIZE_BYTES=$(($MIN_PERSISTENT_SIZE_BYTES + $CONTENT_BASED_PERSISTENT))
    
    # Calculate final image size with state, persistent, and content
    # Partition order: efi, oem, recovery, state, persistent, content
    CALCULATED_IMG_SIZE_BYTES=$(($COS_GRUB_SIZE + $COS_OEM_SIZE + $COS_RECOVERY_SIZE + $STATE_SIZE_BYTES + $PERSISTENT_SIZE_BYTES + $CONTENT_SIZE_BYTES + 1024*1024))
else
    # No content - don't create state/persistent, let Kairos create them
    STATE_SIZE_BYTES=0
    PERSISTENT_SIZE_BYTES=0
    
    # Calculate final image size without state, persistent, or content
    # Partition order: efi, oem, recovery (Kairos will add state and persistent)
    CALCULATED_IMG_SIZE_BYTES=$(($COS_GRUB_SIZE + $COS_OEM_SIZE + $COS_RECOVERY_SIZE + 1024*1024))
fi

FINAL_IMG_SIZE_BYTES=$CALCULATED_IMG_SIZE_BYTES
FINAL_IMG_SIZE=$(numfmt --to=iec "$FINAL_IMG_SIZE_BYTES")

# --- Partition & sizing ---
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    echo "--- Creating and Partitioning Final Image (Pre-create state/persistent approach) ---"
    echo "Partition sizes:"
    echo "  EFI (COS_GRUB): $(numfmt --to=iec $COS_GRUB_SIZE)"
    echo "  OEM: $(numfmt --to=iec $COS_OEM_SIZE)"
    echo "  Recovery: $(numfmt --to=iec $COS_RECOVERY_SIZE)"
    echo "  State: $(numfmt --to=iec $STATE_SIZE_BYTES) (pre-created, Kairos will detect and use)"
    echo "  Persistent: $(numfmt --to=iec $PERSISTENT_SIZE_BYTES) (pre-created, Kairos will detect and use)"
    echo "  Content: $(numfmt --to=iec $CONTENT_SIZE_BYTES) (placed at partition 6, safe at the end)"
    echo ""
    echo "Final image size: $(numfmt --to=iec $FINAL_IMG_SIZE_BYTES) (minimum required)"
    echo ""
    echo "Note: Pre-creating COS_STATE and COS_PERSISTENT with correct labels."
    echo "      Based on Kairos docs: https://kairos.io/docs/reference/configuration/"
    echo "      Kairos creates partitions sequentially: COS_OEM → COS_RECOVERY → COS_STATE → COS_PERSISTENT"
    echo "      By pre-creating with correct labels, Kairos will detect and use existing partitions"
    echo "      instead of creating new ones, preventing content partition from being overwritten."
    echo "      Content partition is placed at partition 6 (after persistent), safe at the end."
    echo "      After content is deleted, persistent will automatically use the full disk space."
    echo ""
else
    echo "--- Creating and Partitioning Final Image (No content - let Kairos create state/persistent) ---"
    echo "Partition sizes:"
    echo "  EFI (COS_GRUB): $(numfmt --to=iec $COS_GRUB_SIZE)"
    echo "  OEM: $(numfmt --to=iec $COS_OEM_SIZE)"
    echo "  Recovery: $(numfmt --to=iec $COS_RECOVERY_SIZE)"
    echo "  State: (will be created by Kairos)"
    echo "  Persistent: (will be created by Kairos)"
    echo ""
    echo "Final image size: $(numfmt --to=iec $FINAL_IMG_SIZE_BYTES) (minimum required)"
    echo ""
    echo "Note: No content partition needed. Kairos will create COS_STATE and COS_PERSISTENT"
    echo "      partitions during boot using the default layout."
    echo ""
fi

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

# Calculate partition positions
# Only calculate state/persistent positions when content exists
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    # Order: efi, oem, recovery, state, persistent, content
    STATE_START_BYTES=$COS_RECOVERY_END_BYTES
    STATE_START="${STATE_START_BYTES}MiB"
    STATE_END_BYTES=$(($STATE_START_BYTES + $STATE_SIZE_BYTES / 1024 / 1024))
    STATE_END="${STATE_END_BYTES}MiB"
    
    PERSISTENT_START_BYTES=$STATE_END_BYTES
    PERSISTENT_START="${PERSISTENT_START_BYTES}MiB"
    PERSISTENT_END_BYTES=$(($PERSISTENT_START_BYTES + $PERSISTENT_SIZE_BYTES / 1024 / 1024))
    PERSISTENT_END="${PERSISTENT_END_BYTES}MiB"
    
    # Content partition position - placed after persistent (partition 6), safe at the end
    CONTENT_START_BYTES=$PERSISTENT_END_BYTES
    CONTENT_START="${CONTENT_START_BYTES}MiB"
    CONTENT_END_BYTES=$(($CONTENT_START_BYTES + $CONTENT_SIZE_BYTES / 1024 / 1024))
    CONTENT_END="${CONTENT_END_BYTES}MiB"
else
    # No content - no state/persistent/content partitions
    STATE_START=""
    STATE_END=""
    PERSISTENT_START=""
    PERSISTENT_END=""
    CONTENT_START=""
    CONTENT_END=""
fi

# Create partitions with pre-created state and persistent
# Based on Kairos documentation: Kairos detects existing partitions with correct labels
# and uses them instead of creating new ones, preventing content from being overwritten
# Partition order: efi, oem, recovery, state, persistent, content
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    echo "Creating partitions: efi, oem, recovery, state, persistent, content"
    # Create all 6 partitions: efi, oem, recovery, state, persistent, content
    parted -s "$FINAL_IMG" -- \
      mklabel gpt \
      mkpart efi fat32 1MiB "$COS_GRUB_END" \
      set 1 esp on \
      mkpart oem ext2 "$COS_GRUB_END" "$COS_OEM_END" \
      mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END" \
      mkpart state ext2 "$STATE_START" "$STATE_END" \
      mkpart persistent ext2 "$PERSISTENT_START" "$PERSISTENT_END" \
      mkpart content ext4 "$CONTENT_START" "$CONTENT_END" \
      name 4 COS_STATE \
      name 5 COS_PERSISTENT \
      name 6 COS_CONTENT \
      set 4 msftdata off \
      set 5 msftdata off \
      set 6 msftdata off || {
        echo "Error: Failed to create partitions" >&2
        exit 1
    }
    # Set partition type GUIDs (using sgdisk if available, otherwise skip)
    if command -v sgdisk >/dev/null 2>&1; then
        echo "Setting partition type GUIDs..."
        sgdisk -t 4:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for state"
        sgdisk -t 5:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for persistent"
        sgdisk -t 6:8300 "$FINAL_IMG" || echo "Warning: Failed to set partition type GUID for content"
    else
        echo "Note: sgdisk not available, skipping partition type GUID setting (parted defaults will be used)"
    fi
    echo "Partitions created successfully"
    echo "Final partition table:"
    parted -s "$FINAL_IMG" print
    echo ""
    echo "Note: Pre-created COS_STATE and COS_PERSISTENT with correct labels."
    echo "      Kairos will detect and use these existing partitions during boot."
    echo "      Content partition is at partition 6, safe at the end."
else
    # No content - create only efi, oem, recovery (let Kairos create state and persistent)
    echo "Creating partitions: efi, oem, recovery (no content, Kairos will create state/persistent)"
    parted -s "$FINAL_IMG" -- \
      mklabel gpt \
      mkpart efi fat32 1MiB "$COS_GRUB_END" \
      set 1 esp on \
      mkpart oem ext2 "$COS_GRUB_END" "$COS_OEM_END" \
      mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END" || {
        echo "Error: Failed to create partitions" >&2
        exit 1
    }
    echo "Partitions created successfully"
    echo "Final partition table:"
    parted -s "$FINAL_IMG" print
    echo ""
    echo "Note: Only efi, oem, and recovery partitions created."
    echo "      Kairos will create COS_STATE and COS_PERSISTENT partitions during boot."
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
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    FINAL_STATE_DEV="${FINAL_PARTS[3]}"
    FINAL_PERSISTENT_DEV="${FINAL_PARTS[4]}"
    FINAL_CONTENT_DEV="${FINAL_PARTS[5]}"
fi

sleep 2

# --- Format and Mount Filesystems ---
echo "--- Formatting and Mounting Partitions ---"
# Use mkfs to apply the desired labels to the newly created partitions
mkfs.vfat -n "COS_GRUB" "$FINAL_EFI_DEV"
mkfs.ext2 -L COS_OEM "$FINAL_OEM_DEV"
mkfs.ext2 -L COS_RECOVERY "$FINAL_RECOVERY_DEV"
# Format state and persistent partitions with correct labels only when content exists
# Kairos will detect these existing partitions and use them instead of creating new ones
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    mkfs.ext2 -L COS_STATE "$FINAL_STATE_DEV"
    mkfs.ext2 -L COS_PERSISTENT "$FINAL_PERSISTENT_DEV"
    mkfs.ext4 -L COS_CONTENT "$FINAL_CONTENT_DEV"
fi

MNT_INPUT_EFI=$(mktemp -d)
MNT_INPUT_OEM=$(mktemp -d)
MNT_INPUT_RECOVERY=$(mktemp -d)

MNT_FINAL_EFI=$(mktemp -d)
MNT_FINAL_OEM=$(mktemp -d)
MNT_FINAL_RECOVERY=$(mktemp -d)
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    MNT_FINAL_CONTENT=$(mktemp -d)
fi

mount -t vfat "$INPUT_EFI_DEV" "$MNT_INPUT_EFI"
mount -t ext2 "$INPUT_OEM_DEV" "$MNT_INPUT_OEM"
mount -t ext2 "$INPUT_RECOVERY_DEV" "$MNT_INPUT_RECOVERY"

mount -t vfat "$FINAL_EFI_DEV" "$MNT_FINAL_EFI"
mount -t ext2 "$FINAL_OEM_DEV" "$MNT_FINAL_OEM"
mount -t ext2 "$FINAL_RECOVERY_DEV" "$MNT_FINAL_RECOVERY"
# Note: State and persistent partitions are pre-created and formatted with correct labels only when content exists
# Kairos will detect and use these existing partitions during boot instead of creating new ones
# We don't need to mount them here since we're not copying any data to them
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
    if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
        echo "Checking for pre-created partitions:"
        blkid "$INPUT_IMG"* 2>/dev/null | grep -i "COS_STATE" || echo "COS_STATE not found in blkid (may need to be mounted)"
        blkid "$INPUT_IMG"* 2>/dev/null | grep -i "COS_PERSISTENT" || echo "COS_PERSISTENT not found in blkid (may need to be mounted)"
        blkid "$INPUT_IMG"* 2>/dev/null | grep -i "COS_CONTENT" || echo "COS_CONTENT not found in blkid (may need to be mounted)"
        echo ""
        echo "Note: COS_STATE and COS_PERSISTENT partitions are pre-created with correct labels."
        echo "      Kairos will detect and use these existing partitions during boot."
    else
        echo "Note: No content partition. COS_STATE and COS_PERSISTENT will be created by Kairos during boot."
    fi
fi
echo ""

# Report final image information
FINAL_IMG_SIZE=$(du -h "$INPUT_IMG" | cut -f1)
echo "Final image with content partition: $INPUT_IMG"
echo "Final image size: $FINAL_IMG_SIZE"
echo "Expected size: ~$(numfmt --to=iec $FINAL_IMG_SIZE_BYTES)"
echo ""

# Cleanup
rm -rf "$MNT_INPUT_EFI" "$MNT_INPUT_OEM" "$MNT_INPUT_RECOVERY" "$MNT_FINAL_EFI" "$MNT_FINAL_OEM" "$MNT_FINAL_RECOVERY"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    rm -rf "$MNT_FINAL_CONTENT"
fi
rm -rf "$WORKDIR"
CLEANUP_DONE=true

echo "✅ Content partition added successfully to image"

exit 0
