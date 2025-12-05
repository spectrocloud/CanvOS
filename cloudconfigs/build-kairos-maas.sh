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
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_kairos_raw_image>" >&2
    exit 1
fi
# Convert the input path to an absolute path to avoid "No such file or directory" error
# after changing to the temporary work directory.
INPUT_IMG=$(readlink -f "$1")
# Store the original directory so we can copy the final image back there.
ORIG_DIR=$(pwd)
# The URL for the Ubuntu cloud image.
UBUNTU_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.tar.gz"
# The name of the final output image.
FINAL_IMG="kairos-ubuntu-maas.raw"
# The size of the new Ubuntu rootfs partition.
UBUNTU_ROOT_SIZE="5G"
# Path to the curtin hooks script (relative to the original directory)
CURTIN_HOOKS_SCRIPT="$ORIG_DIR/curtin-hooks"

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

UBUNTU_ROOT_SIZE_BYTES=$(numfmt --from=iec "$UBUNTU_ROOT_SIZE")
FINAL_IMG_SIZE_BYTES=$(($COS_GRUB_SIZE + $UBUNTU_ROOT_SIZE_BYTES + $COS_OEM_SIZE + $COS_RECOVERY_SIZE + 1024*1024 )) 

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

# Create partitions with names that match the source image.
parted -s "$FINAL_IMG" -- \
  mklabel gpt \
  mkpart efi fat32 1MiB "$COS_GRUB_END" \
  set 1 esp on \
  mkpart ubuntu_rootfs ext4 "$COS_GRUB_END" "$UBUNTU_END" \
  mkpart oem ext2 "$UBUNTU_END" "$COS_OEM_END" \
  mkpart recovery ext2 "$COS_OEM_END" "$COS_RECOVERY_END"


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

sleep 2

# --- Format and Mount Filesystems ---
echo "--- Formatting and Mounting Partitions ---"
# Use mkfs to apply the desired labels to the newly created partitions.
mkfs.vfat -n "COS_GRUB" "$FINAL_EFI_DEV"
mkfs.ext4 -L UBUNTU_ROOTFS "$FINAL_UBUNTU_ROOTFS_DEV"
mkfs.ext2 -L COS_OEM "$FINAL_OEM_DEV"
mkfs.ext2 -L COS_RECOVERY "$FINAL_RECOVERY_DEV"

MNT_INPUT_EFI=$(mktemp -d)
MNT_INPUT_OEM=$(mktemp -d)
MNT_INPUT_RECOVERY=$(mktemp -d)
MNT_UBUNTU_ROOT_IMG=$(mktemp -d)

MNT_FINAL_EFI=$(mktemp -d)
MNT_FINAL_UBUNTU_ROOTFS=$(mktemp -d)
MNT_FINAL_OEM=$(mktemp -d)
MNT_FINAL_RECOVERY=$(mktemp -d)

mount -t vfat "$INPUT_EFI_DEV" "$MNT_INPUT_EFI"
mount -t ext2 "$INPUT_OEM_DEV" "$MNT_INPUT_OEM"
mount -t ext2 "$INPUT_RECOVERY_DEV" "$MNT_INPUT_RECOVERY"
mount "$UBUNTU_LOOP_DEV" "$MNT_UBUNTU_ROOT_IMG"

mount -t vfat "$FINAL_EFI_DEV" "$MNT_FINAL_EFI"
mount "$FINAL_UBUNTU_ROOTFS_DEV" "$MNT_FINAL_UBUNTU_ROOTFS"
mount -t ext2 "$FINAL_OEM_DEV" "$MNT_FINAL_OEM"
mount -t ext2 "$FINAL_RECOVERY_DEV" "$MNT_FINAL_RECOVERY"

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

# Sync all filesystems to ensure data is written
echo "Syncing filesystems..."
sync

# --- Install curtin hooks ---
echo "--- Installing curtin hooks script ---"
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/curtin"
cp "$CURTIN_HOOKS_SCRIPT" "$MNT_FINAL_UBUNTU_ROOTFS/curtin/"
chmod 750 "$MNT_FINAL_UBUNTU_ROOTFS/curtin/curtin-hooks"
echo "Curtin hooks script installed at /curtin/curtin-hooks with 750 permissions"

# --- Install cloud-init userdata processing script ---
echo "--- Installing cloud-init userdata processing script ---"
# Create the cloud-init per-instance scripts directory
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/var/lib/cloud/scripts/per-instance"

# Create the userdata processing script
cat > "$MNT_FINAL_UBUNTU_ROOTFS/var/lib/cloud/scripts/per-instance/setup-recovery.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# Find the partition with the label COS_OEM
OEM_PARTITION=$(blkid -L COS_OEM)
if [ -z "$OEM_PARTITION" ]; then
  echo "Error: COS_OEM partition not found." >&2
  exit 1
fi

# Create a temporary mount point and mount the partition
mkdir -p /mnt/oem_temp
mount -o rw "$OEM_PARTITION" /mnt/oem_temp

# Check if the mount was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to mount COS_OEM partition." >&2
  rmdir /mnt/oem_temp
  exit 1
fi

# Copy the userdata file - cloud-init stores userdata at this location
if [ -f "/var/lib/cloud/instance/user-data.txt" ]; then
  cp /var/lib/cloud/instance/user-data.txt /mnt/oem_temp/userdata.yaml
  echo "Userdata copied to COS_OEM partition"
else
  echo "Warning: /var/lib/cloud/instance/user-data.txt not found"
fi

# Update grubenv to set next_entry to 'recovery'
# Use grub-editenv as it's the safe way to modify this file
grub-editenv /mnt/oem_temp/grubenv set next_entry=recovery

# Unmount the partition
umount /mnt/oem_temp
rmdir /mnt/oem_temp

echo "Script finished successfully."
reboot
EOF

chmod +x "$MNT_FINAL_UBUNTU_ROOTFS/var/lib/cloud/scripts/per-instance/setup-recovery.sh"
echo "Cloud-init userdata processing script installed at /var/lib/cloud/scripts/per-instance/setup-recovery.sh"

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
else
  echo "Warning: $GRUB_ENV_PATH not found, skipping grubenv patch." >&2
fi
# --- Finalize ---
echo "--- Verifying final image before unmounting ---"
# Verify partition table
echo "Final image partition table:"
parted -s "$FINAL_IMG" print
echo ""

# Verify filesystem labels
echo "Filesystem labels:"
blkid "$FINAL_EFI_DEV" "$FINAL_UBUNTU_ROOTFS_DEV" "$FINAL_OEM_DEV" "$FINAL_RECOVERY_DEV" 2>/dev/null || true
echo ""

# Check recovery partition filesystem
echo "Checking recovery partition filesystem integrity..."
e2fsck -n "$FINAL_RECOVERY_DEV" 2>&1 | head -20 || echo "Note: e2fsck check completed"
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

rm -rf "$MNT_INPUT_EFI" "$MNT_INPUT_OEM" "$MNT_INPUT_RECOVERY" "$MNT_UBUNTU_ROOT_IMG" "$MNT_FINAL_EFI" "$MNT_FINAL_UBUNTU_ROOTFS" "$MNT_FINAL_OEM" "$MNT_FINAL_RECOVERY" "$WORKDIR"

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

echo ""
echo "✅ Composite image created and compressed successfully: $COMPRESSED_IMG"
echo "You can now upload this compressed raw image to MAAS (MAAS will automatically decompress it)."
echo "📋 Cloud-init userdata processing script has been integrated - it will:"
echo "   • Run once after cloud-init processes userdata"
echo "   • Copy userdata to COS_OEM partition as userdata.yaml" 
echo "   • Set grubenv to boot recovery mode"
echo "   • Reboot the system"

# Exit with success code
exit 0