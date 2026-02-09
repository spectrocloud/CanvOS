#!/bin/bash -x
#
# This script creates a composite raw disk image for MAAS deployment,
# starting with a Kairos OS base image.
#
# The final image will have the following partition layout, with names matching
# the source image but with custom labels for ease of identification:
# 1. efi (labeled COS_GRUB)
# 2. UBUNTU_ROOTFS (labeled UBUNTU_ROOTFS)
# 3. oem (labeled COS_OEM)
# 4. recovery (labeled COS_RECOVERY)
#
# The script adds a custom GRUB menu entry to the oem partition
# and modifies grubenv to boot this new Ubuntu entry on the first boot.

set -euo pipefail

# --- Configuration ---
# The path to your input Kairos OS raw image.
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <path_to_kairos_raw_image> [maas_image_name]" >&2
    echo "  maas_image_name: Optional custom name for the final MAAS image (without .raw.gz extension)" >&2
    echo "                   Default: kairos-ubuntu-maas" >&2
    exit 1
fi
# Convert the input path to an absolute path to avoid "No such file or directory" error
# after changing to the temporary work directory.
INPUT_IMG=$(readlink -f "$1")
# Store the original directory so we can copy the final image back there.
ORIG_DIR=$(pwd)
# The URL for the Ubuntu cloud image.
UBUNTU_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.tar.gz"
# The name of the final output image (can be customized via parameter or MAAS_IMAGE_NAME env var)
if [ "$#" -eq 2 ]; then
    FINAL_IMG_BASE="$2"
elif [ -n "${MAAS_IMAGE_NAME:-}" ]; then
    FINAL_IMG_BASE="$MAAS_IMAGE_NAME"
else
    FINAL_IMG_BASE="kairos-ubuntu-maas"
fi
# Ensure the name doesn't already have .raw extension
FINAL_IMG_BASE="${FINAL_IMG_BASE%.raw}"
FINAL_IMG="${FINAL_IMG_BASE}.raw"
# The size of the new Ubuntu rootfs partition.
UBUNTU_ROOT_SIZE="3G"
# The size of the content partition (for Stylus content files)
# Default to 2G, but will be calculated based on actual content size if content files exist
CONTENT_SIZE="2G"

CURTIN_HOOKS_SCRIPT="${CURTIN_HOOKS_SCRIPT:-$ORIG_DIR/curtin-hooks}"

CONTENT_BASE_DIR="${CONTENT_BASE_DIR:-$ORIG_DIR}"
# Path to content directory (if content files are provided)
# Look for content-* directories (e.g., content-3a456a58)
CONTENT_DIR=""
for dir in "$CONTENT_BASE_DIR"/content-*; do
    if [ -d "$dir" ]; then
        CONTENT_DIR="$dir"
        echo "Found content directory: $CONTENT_DIR"
        break
    fi
done
# Fallback to plain content directory if no content-* found
if [ -z "$CONTENT_DIR" ] && [ -d "$CONTENT_BASE_DIR/content" ]; then
    CONTENT_DIR="$CONTENT_BASE_DIR/content"
    echo "Found content directory: $CONTENT_DIR"
fi

# Path to cluster config (SPC) file if provided
CLUSTERCONFIG_FILE=""

# --- Tools check ---
for tool in wget tar losetup grub-editenv qemu-img parted kpartx mkfs.ext2 mkfs.vfat mkfs.ext4 rsync blkid; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: Required tool '$tool' is not installed." >&2
        exit 1
    fi
done

# Check if curtin hooks script exists
if [ ! -f "$CURTIN_HOOKS_SCRIPT" ]; then
    echo "Error: Curtin hooks script not found at $CURTIN_HOOKS_SCRIPT" >&2
    exit 1
fi

# --- Temp workspace ---
WORKDIR=$(mktemp -d)
UBUNTU_LOOP_DEV="" # Initialize for the trap
CLEANUP_DONE=false
trap 'EXIT_CODE=$?; \
      if [ "$CLEANUP_DONE" = "false" ]; then \
          echo "Cleaning up..."; \
          umount -l "$WORKDIR"/* &>/dev/null || true; \
          if [ -n "$UBUNTU_LOOP_DEV" ]; then losetup -d "$UBUNTU_LOOP_DEV" &>/dev/null || true; fi; \
          if [ -n "$FINAL_IMG" ]; then kpartx -d "$FINAL_IMG" &>/dev/null || true; fi; \
          if [ -n "$INPUT_IMG" ]; then kpartx -d "$INPUT_IMG" &>/dev/null || true; fi; \
          rm -rf "$WORKDIR" || true; \
          CLEANUP_DONE=true; \
      fi; \
      exit $EXIT_CODE' EXIT
cd "$WORKDIR"

# --- Download & Extract Ubuntu Image ---
echo "--- Downloading and extracting Ubuntu image... ---"
wget -c "$UBUNTU_URL"
UBUNTU_TAR_GZ=$(basename "$UBUNTU_URL")
tar -xzf "$UBUNTU_TAR_GZ"
UBUNTU_IMG=$(find . -name "*.img" -type f -print -quit)
if [ -z "$UBUNTU_IMG" ]; then
    echo "Error: Could not find .img file in the extracted Ubuntu archive." >&2
    exit 1
fi

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

# Correctly extract partition sizes based on names found in parted output (efi, oem, recovery)
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

# Check for SPC file
# Note: We're in WORKDIR at this point, so we need to check ORIG_DIR for files
if [ -f "$ORIG_DIR/spc.tgz" ]; then
    CLUSTERCONFIG_FILE="$ORIG_DIR/spc.tgz"
elif [ -n "${CLUSTERCONFIG:-}" ]; then
    # CLUSTERCONFIG is typically just a filename (e.g., test-69262934779bc4cc94966e66.tgz)
    # Check relative to ORIG_DIR first (most common case)
    if [ -f "$ORIG_DIR/$CLUSTERCONFIG" ]; then
        CLUSTERCONFIG_FILE="$ORIG_DIR/$CLUSTERCONFIG"
    # If not found, try as absolute path
    elif [ -f "$CLUSTERCONFIG" ]; then
        CLUSTERCONFIG_FILE="$CLUSTERCONFIG"
    fi
fi

# Check for EDGE_CUSTOM_CONFIG file (content signing key)
EDGE_CUSTOM_CONFIG_FILE=""
if [ -n "${EDGE_CUSTOM_CONFIG:-}" ]; then
    # EDGE_CUSTOM_CONFIG can be a relative or absolute path
    if [ -f "$EDGE_CUSTOM_CONFIG" ]; then
        EDGE_CUSTOM_CONFIG_FILE="$EDGE_CUSTOM_CONFIG"
        echo "EDGE_CUSTOM_CONFIG file found: $EDGE_CUSTOM_CONFIG_FILE"
    elif [ -f "$ORIG_DIR/$EDGE_CUSTOM_CONFIG" ]; then
        EDGE_CUSTOM_CONFIG_FILE="$ORIG_DIR/$EDGE_CUSTOM_CONFIG"
        echo "EDGE_CUSTOM_CONFIG file found: $EDGE_CUSTOM_CONFIG_FILE"
    fi
fi

# Check if content directory exists and calculate size needed
CONTENT_SIZE_BYTES=0
HAS_CONTENT=false
CONTENT_FILES_SIZE=0

# Calculate size of content files
if [ -d "$CONTENT_DIR" ] && [ -n "$(find "$CONTENT_DIR" -type f \( -name "*.zst" -o -name "*.tar" \) 2>/dev/null | head -1)" ]; then
    CONTENT_FILES_SIZE=$(find "$CONTENT_DIR" -type f \( -name "*.zst" -o -name "*.tar" \) -exec du -cb {} + 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
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
fi
echo ""

UBUNTU_ROOT_SIZE_BYTES=$(numfmt --from=iec "$UBUNTU_ROOT_SIZE")
FINAL_IMG_SIZE_BYTES=$(($COS_GRUB_SIZE + $UBUNTU_ROOT_SIZE_BYTES + $COS_OEM_SIZE + $COS_RECOVERY_SIZE + $CONTENT_SIZE_BYTES + 1024*1024 )) 

FINAL_IMG_SIZE=$(numfmt --to=iec "$FINAL_IMG_SIZE_BYTES")

# --- Partition & sizing ---
echo "--- Creating and Partitioning Final Image ---"
qemu-img create -f raw "$FINAL_IMG" "$FINAL_IMG_SIZE"

# Partition offsets
COS_GRUB_END_BYTES=$(($COS_GRUB_SIZE / 1024 / 1024))
COS_GRUB_END="${COS_GRUB_END_BYTES}MiB"
UBUNTU_END_BYTES=$(($COS_GRUB_END_BYTES + $UBUNTU_ROOT_SIZE_BYTES / 1024 / 1024))
UBUNTU_END="${UBUNTU_END_BYTES}MiB"
COS_OEM_END_BYTES=$(($UBUNTU_END_BYTES + $COS_OEM_SIZE / 1024 / 1024))
COS_OEM_END="${COS_OEM_END_BYTES}MiB"
# Calculate the fixed end point for the recovery partition
COS_RECOVERY_END_BYTES=$(($COS_OEM_END_BYTES + $COS_RECOVERY_SIZE / 1024 / 1024))
COS_RECOVERY_END="${COS_RECOVERY_END_BYTES}MiB"

# Calculate content partition end point (if content exists)
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    CONTENT_END_BYTES=$(($COS_RECOVERY_END_BYTES + $CONTENT_SIZE_BYTES / 1024 / 1024))
    CONTENT_END="${CONTENT_END_BYTES}MiB"
else
    CONTENT_END="$COS_RECOVERY_END"
fi

# Create partitions with names that match the source image.
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    parted -s "$FINAL_IMG" -- \
      mklabel gpt \
      mkpart efi fat32 1MiB "$COS_GRUB_END" \
      set 1 esp on \
      mkpart ubuntu_rootfs ext4 "$COS_GRUB_END" "$UBUNTU_END" \
      mkpart oem ext2 "$UBUNTU_END" "$COS_OEM_END" \
      mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END" \
      mkpart content ext4 "$COS_RECOVERY_END" "$CONTENT_END"
else
    parted -s "$FINAL_IMG" -- \
      mklabel gpt \
      mkpart efi fat32 1MiB "$COS_GRUB_END" \
      set 1 esp on \
      mkpart ubuntu_rootfs ext4 "$COS_GRUB_END" "$UBUNTU_END" \
      mkpart oem ext2 "$UBUNTU_END" "$COS_OEM_END" \
      mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END"
fi


# --- Loop setup for device mapping ---
echo "--- Setting up loop devices ---"
INPUT_PARTS=($(kpartx -avs "$INPUT_IMG" | awk '{print "/dev/mapper/" $3}'))
# Use the correct index from kpartx output based on partition order.
INPUT_EFI_DEV="${INPUT_PARTS[0]}"
INPUT_OEM_DEV="${INPUT_PARTS[1]}"
INPUT_RECOVERY_DEV="${INPUT_PARTS[2]}"

UBUNTU_LOOP_DEV=$(losetup -f --show "$UBUNTU_IMG")
echo "Attached Ubuntu image to $UBUNTU_LOOP_DEV"

FINAL_PARTS=($(kpartx -avs "$FINAL_IMG" | awk '{print "/dev/mapper/" $3}'))
FINAL_EFI_DEV="${FINAL_PARTS[0]}"
FINAL_UBUNTU_ROOTFS_DEV="${FINAL_PARTS[1]}"
FINAL_OEM_DEV="${FINAL_PARTS[2]}"
FINAL_RECOVERY_DEV="${FINAL_PARTS[3]}"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    FINAL_CONTENT_DEV="${FINAL_PARTS[4]}"
fi

sleep 2

# --- Format and Mount Filesystems ---
echo "--- Formatting and Mounting Partitions ---"
# Use mkfs to apply the desired labels to the newly created partitions.
mkfs.vfat -n "COS_GRUB" "$FINAL_EFI_DEV"
mkfs.ext4 -L UBUNTU_ROOTFS "$FINAL_UBUNTU_ROOTFS_DEV"
mkfs.ext2 -L COS_OEM "$FINAL_OEM_DEV"
mkfs.ext2 -L COS_RECOVERY "$FINAL_RECOVERY_DEV"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    mkfs.ext4 -L COS_CONTENT "$FINAL_CONTENT_DEV"
fi

MNT_INPUT_EFI=$(mktemp -d)
MNT_INPUT_OEM=$(mktemp -d)
MNT_INPUT_RECOVERY=$(mktemp -d)
MNT_UBUNTU_ROOT_IMG=$(mktemp -d)

MNT_FINAL_EFI=$(mktemp -d)
MNT_FINAL_UBUNTU_ROOTFS=$(mktemp -d)
MNT_FINAL_OEM=$(mktemp -d)
MNT_FINAL_RECOVERY=$(mktemp -d)
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    MNT_FINAL_CONTENT=$(mktemp -d)
fi

mount -t vfat "$INPUT_EFI_DEV" "$MNT_INPUT_EFI"
mount -t ext2 "$INPUT_OEM_DEV" "$MNT_INPUT_OEM"
mount -t ext2 "$INPUT_RECOVERY_DEV" "$MNT_INPUT_RECOVERY"
mount "$UBUNTU_LOOP_DEV" "$MNT_UBUNTU_ROOT_IMG"

mount -t vfat "$FINAL_EFI_DEV" "$MNT_FINAL_EFI"
mount "$FINAL_UBUNTU_ROOTFS_DEV" "$MNT_FINAL_UBUNTU_ROOTFS"
mount -t ext2 "$FINAL_OEM_DEV" "$MNT_FINAL_OEM"
mount -t ext2 "$FINAL_RECOVERY_DEV" "$MNT_FINAL_RECOVERY"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    mount "$FINAL_CONTENT_DEV" "$MNT_FINAL_CONTENT"
fi

# --- Copy Filesystems ---
echo "--- Copying Filesystem Data ---"
echo "Copying EFI partition..."
rsync -aHAX --info=progress2 "$MNT_INPUT_EFI/" "$MNT_FINAL_EFI/" || { echo "Error: Failed to copy EFI partition"; exit 1; }
echo "Copying Ubuntu root filesystem..."
rsync -aHAX --info=progress2 "$MNT_UBUNTU_ROOT_IMG/" "$MNT_FINAL_UBUNTU_ROOTFS/" || { echo "Error: Failed to copy Ubuntu root filesystem"; exit 1; }
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
        find "$CONTENT_DIR" -type f \( -name "*.zst" -o -name "*.tar" \) -exec cp -v {} "$MNT_FINAL_CONTENT/bundle-content/" \;
        BUNDLE_COUNT=$(find "$MNT_FINAL_CONTENT/bundle-content" -type f | wc -l)
        echo "Copied $BUNDLE_COUNT content file(s) to bundle-content folder"
    fi
    
    # Copy SPC file if it exists to spc-config folder (preserve original filename)
    if [ -n "$CLUSTERCONFIG_FILE" ] && [ -f "$CLUSTERCONFIG_FILE" ]; then
        SPC_FILENAME=$(basename "$CLUSTERCONFIG_FILE")
        cp -v "$CLUSTERCONFIG_FILE" "$MNT_FINAL_CONTENT/spc-config/$SPC_FILENAME"
        echo "Copied SPC file to spc-config folder: $SPC_FILENAME"
    fi
    
    # Copy EDGE_CUSTOM_CONFIG file if it exists to edge-config folder (will be copied to /oem/.edge_custom_config.yaml by maas-content.sh)
    if [ -n "$EDGE_CUSTOM_CONFIG_FILE" ] && [ -f "$EDGE_CUSTOM_CONFIG_FILE" ]; then
        cp -v "$EDGE_CUSTOM_CONFIG_FILE" "$MNT_FINAL_CONTENT/edge-config/.edge_custom_config.yaml"
        echo "Copied EDGE_CUSTOM_CONFIG file to edge-config folder"
    fi
    
    CONTENT_COUNT=$(find "$MNT_FINAL_CONTENT" -type f | wc -l)
    echo "Total files in content partition: $CONTENT_COUNT"
    echo "Content partition usage:"
    df -h "$MNT_FINAL_CONTENT" || true
fi

# Sync all filesystems to ensure data is written
echo "Syncing filesystems..."
sync

# --- Install curtin hooks ---
echo "--- Installing curtin hooks script ---"
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/curtin"
cp "$CURTIN_HOOKS_SCRIPT" "$MNT_FINAL_UBUNTU_ROOTFS/curtin/"
chmod 750 "$MNT_FINAL_UBUNTU_ROOTFS/curtin/curtin-hooks"
echo "Curtin hooks script installed at /curtin/curtin-hooks with 750 permissions"


# --- Install one-time setup script ---
echo "--- Installing one-time setup script ---"
# Create systemd service directory
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/etc/systemd/system"

# Create the setup script
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/opt/spectrocloud/scripts"
cat > "$MNT_FINAL_UBUNTU_ROOTFS/opt/spectrocloud/scripts/setup-recovery.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# One-time setup script that runs on first boot
# This script copies MAAS UI userdata to OEM partition and ensures the system boots into recovery mode

MARKER_FILE="/var/lib/setup-recovery-completed"

# Check if this script has already run successfully
if [ -f "$MARKER_FILE" ]; then
  exit 0
fi

# Find the partition with the label COS_OEM
OEM_PARTITION=$(blkid -L COS_OEM)
if [ -z "$OEM_PARTITION" ]; then
  echo "Error: COS_OEM partition not found." >&2
  exit 1
fi

# Create a temporary mount point and mount the partition
OEM_MOUNT=$(mktemp -d) || {
  echo "Error: Failed to create temporary mount point" >&2
  exit 1
}

if ! mount -o rw "$OEM_PARTITION" "$OEM_MOUNT"; then
  echo "Error: Failed to mount COS_OEM partition." >&2
  rmdir "$OEM_MOUNT"
  exit 1
fi

# Track if all operations succeed
SUCCESS=true

# Handle MAAS-provided userdata (from cloud-init) -> userdata.yaml
if [ -f "/var/lib/cloud/instance/user-data.txt" ]; then
  if ! cp /var/lib/cloud/instance/user-data.txt "$OEM_MOUNT/userdata.yaml"; then
    echo "Error: Failed to copy MAAS userdata to COS_OEM partition" >&2
    SUCCESS=false
  fi
fi

# Update grubenv to set next_entry to 'recovery'
if ! grub-editenv "$OEM_MOUNT/grubenv" set next_entry=recovery; then
  echo "Error: Failed to update grubenv" >&2
  SUCCESS=false
fi

# Unmount the partition
if ! umount "$OEM_MOUNT"; then
  echo "Error: Failed to unmount OEM partition" >&2
  SUCCESS=false
fi
rmdir "$OEM_MOUNT"

# Mark script as completed if successful
if [ "$SUCCESS" = "true" ]; then
  mkdir -p "$(dirname "$MARKER_FILE")"
  touch "$MARKER_FILE"
  reboot
else
  echo "Error: Script failed. Not rebooting to allow debugging." >&2
  exit 1
fi
EOF

chmod +x "$MNT_FINAL_UBUNTU_ROOTFS/opt/spectrocloud/scripts/setup-recovery.sh"

# Create systemd service that runs once on first boot
cat > "$MNT_FINAL_UBUNTU_ROOTFS/etc/systemd/system/setup-recovery.service" << 'EOF'
[Unit]
Description=One-time setup script for MAAS deployment
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/var/lib/setup-recovery-completed

[Service]
Type=oneshot
ExecStart=/opt/spectrocloud/scripts/setup-recovery.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/setup-recovery.service "$MNT_FINAL_UBUNTU_ROOTFS/etc/systemd/system/multi-user.target.wants/setup-recovery.service"

echo "One-time setup script and systemd service installed"

# --- Patch GRUB Configuration ---
echo "--- Patching GRUB Configuration for Ubuntu boot ---"
# Add Ubuntu menuentry to a new grubcustom file on the COS_OEM partition
GRUB_CUSTOM_PATH="$MNT_FINAL_OEM/grubcustom"
if [ ! -f "$GRUB_CUSTOM_PATH" ]; then
  # If the file doesn't exist, create it.
  touch "$GRUB_CUSTOM_PATH"
fi
cat >> "$GRUB_CUSTOM_PATH" <<EOF
menuentry 'MAAS Kairos Setup' --id 'ubuntu-firstboot' {
  search --no-floppy --label --set=root UBUNTU_ROOTFS
  set img=/boot/vmlinuz
  set initrd=/boot/initrd.img
  linux (\$root)\$img root=LABEL=UBUNTU_ROOTFS rw console=tty1 console=ttyS0,115200n8
  initrd (\$root)\$initrd
}
EOF
echo "Ubuntu menuentry added to $GRUB_CUSTOM_PATH"

# Patch grubenv to set new entry as default
GRUB_ENV_PATH="$MNT_FINAL_OEM/grubenv"
if [ -f "$GRUB_ENV_PATH" ]; then
  cp "$GRUB_ENV_PATH" "${GRUB_ENV_PATH}.bak"
  
  # Change the next_entry to our new Ubuntu ID
  grub-editenv  "$GRUB_ENV_PATH" set next_entry="ubuntu-firstboot"
  echo "grubenv patched to boot Ubuntu first."
fi
# --- Finalize ---
echo "--- Verifying final image before unmounting ---"
# Verify partition table
echo "Final image partition table:"
parted -s "$FINAL_IMG" print
echo ""

# Verify filesystem labels
echo "Filesystem labels:"
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    blkid "$FINAL_EFI_DEV" "$FINAL_UBUNTU_ROOTFS_DEV" "$FINAL_OEM_DEV" "$FINAL_RECOVERY_DEV" "$FINAL_CONTENT_DEV" 2>/dev/null || true
else
    blkid "$FINAL_EFI_DEV" "$FINAL_UBUNTU_ROOTFS_DEV" "$FINAL_OEM_DEV" "$FINAL_RECOVERY_DEV" 2>/dev/null || true
fi
echo ""

# Check recovery partition filesystem
echo "Checking recovery partition filesystem integrity..."
e2fsck -n "$FINAL_RECOVERY_DEV" 2>&1 | head -20 || true
echo ""

echo "--- Unmounting all mount points and cleaning up loop devices and temp directory ---"
umount -l "$MNT_INPUT_EFI" || true
umount -l "$MNT_INPUT_OEM" || true
umount -l "$MNT_INPUT_RECOVERY" || true
umount -l "$MNT_UBUNTU_ROOT_IMG" || true
umount -l "$MNT_FINAL_EFI" || true
umount -l "$MNT_FINAL_UBUNTU_ROOTFS" || true
umount -l "$MNT_FINAL_OEM" || true
umount -l "$MNT_FINAL_RECOVERY" || true
if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    umount -l "$MNT_FINAL_CONTENT" || true
fi

if [ -n "$UBUNTU_LOOP_DEV" ]; then losetup -d "$UBUNTU_LOOP_DEV" || true; fi
kpartx -d "$FINAL_IMG" || true
kpartx -d "$INPUT_IMG" || true
echo "--- Copying final image to original directory... ---"
cp "$FINAL_IMG" "$ORIG_DIR/"

# Report final image information
FINAL_IMG_PATH="$ORIG_DIR/$FINAL_IMG"
FINAL_IMG_SIZE=$(du -h "$FINAL_IMG_PATH" | cut -f1)
echo "Final composite image created: $FINAL_IMG_PATH"
echo "Final image size: $FINAL_IMG_SIZE"
echo "Expected size: ~$(numfmt --to=iec $FINAL_IMG_SIZE_BYTES)"
echo ""

if [ "$HAS_CONTENT" = "true" ] && [ "$CONTENT_SIZE_BYTES" -gt 0 ]; then
    rm -rf "$MNT_INPUT_EFI" "$MNT_INPUT_OEM" "$MNT_INPUT_RECOVERY" "$MNT_UBUNTU_ROOT_IMG" "$MNT_FINAL_EFI" "$MNT_FINAL_UBUNTU_ROOTFS" "$MNT_FINAL_OEM" "$MNT_FINAL_RECOVERY" "$MNT_FINAL_CONTENT" "$WORKDIR"
else
    rm -rf "$MNT_INPUT_EFI" "$MNT_INPUT_OEM" "$MNT_INPUT_RECOVERY" "$MNT_UBUNTU_ROOT_IMG" "$MNT_FINAL_EFI" "$MNT_FINAL_UBUNTU_ROOTFS" "$MNT_FINAL_OEM" "$MNT_FINAL_RECOVERY" "$WORKDIR"
fi

# Mark cleanup as done so trap doesn't try again
CLEANUP_DONE=true

echo ""
echo "--- Compressing final image (this may take a few minutes) ---"
FINAL_IMG_PATH="$ORIG_DIR/$FINAL_IMG"
COMPRESSED_IMG="${FINAL_IMG_PATH}.gz"
ORIG_SIZE=$(du -h "$FINAL_IMG_PATH" | cut -f1)
echo "Original size: $ORIG_SIZE"
echo "Compressing to $COMPRESSED_IMG..."
gzip -c "$FINAL_IMG_PATH" > "$COMPRESSED_IMG" || { echo "Error: Failed to compress image"; exit 1; }
COMP_SIZE=$(du -h "$COMPRESSED_IMG" | cut -f1)
echo "Compressed size: $COMP_SIZE"
echo "Removing uncompressed image to save space..."
rm -f "$FINAL_IMG_PATH"

# Clean up the input kairos-raw image since we no longer need it
if [ -f "$INPUT_IMG" ]; then
    echo "Removing input kairos-raw image to save space: $INPUT_IMG"
    rm -f "$INPUT_IMG"
fi

# Generate SHA256 checksum
echo "Generating SHA256 checksum..."
sha256sum "$COMPRESSED_IMG" > "${COMPRESSED_IMG}.sha256"
CHECKSUM=$(cat "${COMPRESSED_IMG}.sha256" | cut -d' ' -f1)
echo "SHA256: $CHECKSUM"

echo ""
echo "✅ Composite image created and compressed successfully: $COMPRESSED_IMG"
echo "   Size: $COMP_SIZE"
echo "   Checksum: ${COMPRESSED_IMG}.sha256"
echo "You can now upload this compressed raw image to MAAS (MAAS will automatically decompress it)."

# Exit with success code
exit 0