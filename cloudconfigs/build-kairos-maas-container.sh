#!/bin/bash -x
#
# This script creates a composite raw disk image for MAAS deployment,
# starting with a Kairos OS base image. Modified to work in container environments.
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
    echo "Usage: $0 <path_to_kairos_raw_image> [path_to_curtin_hooks]" >&2
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

# Determine the path to the curtin hooks script
# Priority: 1) explicit parameter, 2) current directory, 3) ORIG_DIR, 4) script directory
if [ "$#" -eq 2 ]; then
    # Use explicit path if provided
    CURTIN_HOOKS_SCRIPT="$2"
    if [ ! -f "$CURTIN_HOOKS_SCRIPT" ]; then
        CURTIN_HOOKS_SCRIPT=$(readlink -f "$2" 2>/dev/null || echo "$2")
    fi
elif [ -f "./curtin-hooks" ]; then
    # Check current directory
    CURTIN_HOOKS_SCRIPT=$(readlink -f "./curtin-hooks" 2>/dev/null || echo "$(pwd)/curtin-hooks")
elif [ -f "$ORIG_DIR/curtin-hooks" ]; then
    # Check original directory
    CURTIN_HOOKS_SCRIPT="$ORIG_DIR/curtin-hooks"
else
    # Check script directory as last resort
    SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
    if [ -f "$SCRIPT_DIR/curtin-hooks" ]; then
        CURTIN_HOOKS_SCRIPT="$SCRIPT_DIR/curtin-hooks"
    else
        CURTIN_HOOKS_SCRIPT="$ORIG_DIR/curtin-hooks"
    fi
fi

# --- Tools check ---
for tool in wget tar losetup grub-editenv qemu-img parted mkfs.ext2 mkfs.vfat mkfs.ext4 rsync blkid; do
    if ! command -v $tool &> /dev/null; then
        echo "Error: Required tool '$tool' is not installed." >&2
        exit 1
    fi
done

# Check if curtin hooks script exists
if [ ! -f "$CURTIN_HOOKS_SCRIPT" ]; then
    echo "Error: Curtin hooks script not found at $CURTIN_HOOKS_SCRIPT" >&2
    echo "Searched in: current directory, $ORIG_DIR, and script directory" >&2
    exit 1
fi

# Convert to absolute path for reliability
CURTIN_HOOKS_SCRIPT=$(readlink -f "$CURTIN_HOOKS_SCRIPT" 2>/dev/null || echo "$CURTIN_HOOKS_SCRIPT")
echo "Using curtin-hooks at: $CURTIN_HOOKS_SCRIPT"

# --- Temp workspace ---
WORKDIR=$(mktemp -d)
UBUNTU_LOOP_DEV="" # Initialize for the trap
INPUT_EFI_LOOP="" # Initialize for the trap
INPUT_OEM_LOOP="" # Initialize for the trap
INPUT_RECOVERY_LOOP="" # Initialize for the trap
FINAL_EFI_LOOP="" # Initialize for the trap
FINAL_UBUNTU_LOOP="" # Initialize for the trap
FINAL_OEM_LOOP="" # Initialize for the trap
FINAL_RECOVERY_LOOP="" # Initialize for the trap
PROGRESS_PIDS="" # Track background progress monitoring processes
CLEANUP_DONE=false
trap 'if [ "$CLEANUP_DONE" = "false" ]; then \
      echo "Cleaning up..."; \
      for pid in $PROGRESS_PIDS; do kill $pid 2>/dev/null || true; done; \
      umount -l "$WORKDIR"/* 2>/dev/null || true; \
      if [ -n "$INPUT_EFI_LOOP" ]; then losetup -d "$INPUT_EFI_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$INPUT_OEM_LOOP" ]; then losetup -d "$INPUT_OEM_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$INPUT_RECOVERY_LOOP" ]; then losetup -d "$INPUT_RECOVERY_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$FINAL_EFI_LOOP" ]; then losetup -d "$FINAL_EFI_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$FINAL_UBUNTU_LOOP" ]; then losetup -d "$FINAL_UBUNTU_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$FINAL_OEM_LOOP" ]; then losetup -d "$FINAL_OEM_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$FINAL_RECOVERY_LOOP" ]; then losetup -d "$FINAL_RECOVERY_LOOP" 2>/dev/null || true; fi; \
      if [ -n "$UBUNTU_LOOP_DEV" ]; then losetup -d "$UBUNTU_LOOP_DEV" 2>/dev/null || true; fi; \
      rm -rf "$WORKDIR" 2>/dev/null || true; \
      fi' EXIT
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
# Correctly extract partition sizes based on names found in parted output (efi, oem, recovery)
COS_GRUB_START=$(echo "$INPUT_PARTS_INFO" | grep "efi" | awk '{print $2}' | tr -d 'B')
COS_GRUB_SIZE=$(echo "$INPUT_PARTS_INFO" | grep "efi" | awk '{print $4}' | tr -d 'B')
COS_OEM_START=$(echo "$INPUT_PARTS_INFO" | grep "oem" | awk '{print $2}' | tr -d 'B')
COS_OEM_SIZE=$(echo "$INPUT_PARTS_INFO" | grep "oem" | awk '{print $4}' | tr -d 'B')
COS_RECOVERY_START=$(echo "$INPUT_PARTS_INFO" | grep "recovery" | awk '{print $2}' | tr -d 'B')
COS_RECOVERY_SIZE=$(echo "$INPUT_PARTS_INFO" | grep "recovery" | awk '{print $4}' | tr -d 'B')

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

# --- Create temporary files for partitions ---
echo "--- Creating temporary partition files ---"
# Extract partitions using dd
INPUT_EFI_FILE="input_efi.img"
INPUT_OEM_FILE="input_oem.img"
INPUT_RECOVERY_FILE="input_recovery.img"

# Calculate partition sizes in MB for dd
COS_GRUB_SIZE_MB=$((COS_GRUB_SIZE / 1048576))
COS_OEM_SIZE_MB=$((COS_OEM_SIZE / 1048576))
COS_RECOVERY_SIZE_MB=$((COS_RECOVERY_SIZE / 1048576))

# Calculate skip values in MB
COS_GRUB_SKIP_MB=$((COS_GRUB_START / 1048576))
COS_OEM_SKIP_MB=$((COS_OEM_START / 1048576))
COS_RECOVERY_SKIP_MB=$((COS_RECOVERY_START / 1048576))

# Extract partitions using dd
echo "--- Extracting partitions from input image ---"
echo "Extracting EFI partition (skip=$COS_GRUB_SKIP_MB, count=$COS_GRUB_SIZE_MB)"
dd if="$INPUT_IMG" of="$INPUT_EFI_FILE" bs=1M skip=$COS_GRUB_SKIP_MB count=$COS_GRUB_SIZE_MB || { echo "Failed to extract EFI partition"; exit 1; }
echo "Extracting OEM partition (skip=$COS_OEM_SKIP_MB, count=$COS_OEM_SIZE_MB)"
dd if="$INPUT_IMG" of="$INPUT_OEM_FILE" bs=1M skip=$COS_OEM_SKIP_MB count=$COS_OEM_SIZE_MB || { echo "Failed to extract OEM partition"; exit 1; }
echo "Extracting Recovery partition (skip=$COS_RECOVERY_SKIP_MB, count=$COS_RECOVERY_SIZE_MB)"
dd if="$INPUT_IMG" of="$INPUT_RECOVERY_FILE" bs=1M skip=$COS_RECOVERY_SKIP_MB count=$COS_RECOVERY_SIZE_MB || { echo "Failed to extract Recovery partition"; exit 1; }

# Create mount points
MNT_INPUT_EFI=$(mktemp -d)
MNT_INPUT_OEM=$(mktemp -d)
MNT_INPUT_RECOVERY=$(mktemp -d)
MNT_UBUNTU_ROOT_IMG=$(mktemp -d)

MNT_FINAL_EFI=$(mktemp -d)
MNT_FINAL_UBUNTU_ROOTFS=$(mktemp -d)
MNT_FINAL_OEM=$(mktemp -d)
MNT_FINAL_RECOVERY=$(mktemp -d)

# Mount input partitions using the extracted files instead of losetup with offset
# This avoids issues with large partitions and losetup sizelimit
UBUNTU_LOOP_DEV=$(losetup -f --show "$UBUNTU_IMG")
echo "Attached Ubuntu image to $UBUNTU_LOOP_DEV"

# --- Format and Mount Final Filesystems ---
echo "--- Formatting and Mounting Final Partitions ---"
# Create temporary files for final partitions
FINAL_EFI_FILE="final_efi.img"
FINAL_UBUNTU_FILE="final_ubuntu.img"
FINAL_OEM_FILE="final_oem.img"
FINAL_RECOVERY_FILE="final_recovery.img"

# Create partition files with proper sizes
echo "--- Creating final partition files ---"
echo "Creating final EFI file (size: $COS_GRUB_SIZE_MB MB)"
dd if=/dev/zero of="$FINAL_EFI_FILE" bs=1M count=$COS_GRUB_SIZE_MB || { echo "Failed to create final EFI file"; exit 1; }
echo "Creating final Ubuntu file (size: $((UBUNTU_ROOT_SIZE_BYTES / 1048576)) MB)"
dd if=/dev/zero of="$FINAL_UBUNTU_FILE" bs=1M count=$((UBUNTU_ROOT_SIZE_BYTES / 1048576)) || { echo "Failed to create final Ubuntu file"; exit 1; }
echo "Creating final OEM file (size: $COS_OEM_SIZE_MB MB)"
dd if=/dev/zero of="$FINAL_OEM_FILE" bs=1M count=$COS_OEM_SIZE_MB || { echo "Failed to create final OEM file"; exit 1; }
echo "Creating final Recovery file (size: $COS_RECOVERY_SIZE_MB MB)"
dd if=/dev/zero of="$FINAL_RECOVERY_FILE" bs=1M count=$COS_RECOVERY_SIZE_MB || { echo "Failed to create final Recovery file"; exit 1; }

# Format the partition files
mkfs.vfat -n "COS_GRUB" -F 32 "$FINAL_EFI_FILE"
mkfs.ext4 -L UBUNTU_ROOTFS "$FINAL_UBUNTU_FILE"
mkfs.ext2 -L COS_OEM "$FINAL_OEM_FILE"
mkfs.ext2 -L COS_RECOVERY "$FINAL_RECOVERY_FILE"

# Mount partitions using the extracted files
# Use losetup to create loop devices explicitly (mount -o loop doesn't work in this container)
# Ensure loop module is loaded
modprobe loop 2>/dev/null || true

# Convert all file paths to absolute paths
INPUT_EFI_FILE_ABS=$(readlink -f "$INPUT_EFI_FILE" 2>/dev/null || echo "$WORKDIR/$INPUT_EFI_FILE")
INPUT_OEM_FILE_ABS=$(readlink -f "$INPUT_OEM_FILE" 2>/dev/null || echo "$WORKDIR/$INPUT_OEM_FILE")
INPUT_RECOVERY_FILE_ABS=$(readlink -f "$INPUT_RECOVERY_FILE" 2>/dev/null || echo "$WORKDIR/$INPUT_RECOVERY_FILE")
FINAL_EFI_FILE_ABS=$(readlink -f "$FINAL_EFI_FILE" 2>/dev/null || echo "$WORKDIR/$FINAL_EFI_FILE")
FINAL_UBUNTU_FILE_ABS=$(readlink -f "$FINAL_UBUNTU_FILE" 2>/dev/null || echo "$WORKDIR/$FINAL_UBUNTU_FILE")
FINAL_OEM_FILE_ABS=$(readlink -f "$FINAL_OEM_FILE" 2>/dev/null || echo "$WORKDIR/$FINAL_OEM_FILE")
FINAL_RECOVERY_FILE_ABS=$(readlink -f "$FINAL_RECOVERY_FILE" 2>/dev/null || echo "$WORKDIR/$FINAL_RECOVERY_FILE")

# Helper function to find and use an available loop device
find_loop_device() {
    local file="$1"
    # First, try losetup -f which should work (it worked for Ubuntu image)
    local loop_dev
    loop_dev=$(losetup -f --show "$file" 2>&1)
    local losetup_exit=$?
    if [ $losetup_exit -eq 0 ] && [ -n "$loop_dev" ] && [ -e "$loop_dev" ]; then
        echo "$loop_dev"
        return 0
    else
        # Log the error for debugging (but don't include it in the return value)
        echo "losetup -f failed (exit $losetup_exit): $loop_dev" >&2
    fi
    # If that fails, try explicit loop devices (try higher numbers first to avoid conflicts)
    for i in {16..31} {0..15}; do
        local loop_dev="/dev/loop$i"
        # Create loop device if it doesn't exist
        if [ ! -e "$loop_dev" ]; then
            if ! mknod -m 0660 "$loop_dev" b 7 "$i" 2>/dev/null; then
                continue
            fi
        fi
        # Check if loop device is available (losetup without file returns non-zero if not in use)
        if losetup "$loop_dev" >/dev/null 2>&1; then
            # Device is in use, try next
            continue
        fi
        # Try to set up the loop device
        if losetup "$loop_dev" "$file" 2>/dev/null; then
            echo "$loop_dev"
            return 0
        fi
    done
    echo "Error: Could not find or create an available loop device for $file" >&2
    echo "Currently used loop devices:" >&2
    losetup -a >&2 || true
    return 1
}

echo "--- Mounting input partitions ---"
echo "Mounting EFI partition: $INPUT_EFI_FILE_ABS"
if [ ! -f "$INPUT_EFI_FILE_ABS" ]; then
    echo "Error: File not found: $INPUT_EFI_FILE_ABS"
    ls -la "$WORKDIR" || true
    exit 1
fi
INPUT_EFI_LOOP=$(find_loop_device "$INPUT_EFI_FILE_ABS") || { echo "Failed to create loop device for EFI partition"; exit 1; }
mount -t vfat "$INPUT_EFI_LOOP" "$MNT_INPUT_EFI" || { echo "Failed to mount EFI partition"; losetup -d "$INPUT_EFI_LOOP" 2>/dev/null || true; exit 1; }

echo "Mounting OEM partition: $INPUT_OEM_FILE_ABS"
if [ ! -f "$INPUT_OEM_FILE_ABS" ]; then
    echo "Error: File not found: $INPUT_OEM_FILE_ABS"
    exit 1
fi
INPUT_OEM_LOOP=$(find_loop_device "$INPUT_OEM_FILE_ABS") || { echo "Failed to create loop device for OEM partition"; exit 1; }
mount -t ext2 "$INPUT_OEM_LOOP" "$MNT_INPUT_OEM" || { echo "Failed to mount OEM partition"; losetup -d "$INPUT_OEM_LOOP" 2>/dev/null || true; exit 1; }

echo "Mounting Recovery partition: $INPUT_RECOVERY_FILE_ABS"
if [ ! -f "$INPUT_RECOVERY_FILE_ABS" ]; then
    echo "Error: File not found: $INPUT_RECOVERY_FILE_ABS"
    exit 1
fi
INPUT_RECOVERY_LOOP=$(find_loop_device "$INPUT_RECOVERY_FILE_ABS") || { echo "Failed to create loop device for Recovery partition"; exit 1; }
mount -t ext2 "$INPUT_RECOVERY_LOOP" "$MNT_INPUT_RECOVERY" || { echo "Failed to mount Recovery partition"; losetup -d "$INPUT_RECOVERY_LOOP" 2>/dev/null || true; exit 1; }

echo "Mounting Ubuntu image: $UBUNTU_LOOP_DEV"
mount "$UBUNTU_LOOP_DEV" "$MNT_UBUNTU_ROOT_IMG" || { echo "Failed to mount Ubuntu image"; exit 1; }

echo "--- Mounting final partitions ---"
echo "Mounting final EFI partition: $FINAL_EFI_FILE_ABS"
if [ ! -f "$FINAL_EFI_FILE_ABS" ]; then
    echo "Error: File not found: $FINAL_EFI_FILE_ABS"
    exit 1
fi
FINAL_EFI_LOOP=$(find_loop_device "$FINAL_EFI_FILE_ABS") || { echo "Failed to create loop device for final EFI partition"; exit 1; }
mount -t vfat "$FINAL_EFI_LOOP" "$MNT_FINAL_EFI" || { echo "Failed to mount final EFI partition"; losetup -d "$FINAL_EFI_LOOP" 2>/dev/null || true; exit 1; }

echo "Mounting final Ubuntu partition: $FINAL_UBUNTU_FILE_ABS"
if [ ! -f "$FINAL_UBUNTU_FILE_ABS" ]; then
    echo "Error: File not found: $FINAL_UBUNTU_FILE_ABS"
    exit 1
fi
FINAL_UBUNTU_LOOP=$(find_loop_device "$FINAL_UBUNTU_FILE_ABS") || { echo "Failed to create loop device for final Ubuntu partition"; exit 1; }
mount -t ext4 "$FINAL_UBUNTU_LOOP" "$MNT_FINAL_UBUNTU_ROOTFS" || { echo "Failed to mount final Ubuntu partition"; losetup -d "$FINAL_UBUNTU_LOOP" 2>/dev/null || true; exit 1; }

echo "Mounting final OEM partition: $FINAL_OEM_FILE_ABS"
if [ ! -f "$FINAL_OEM_FILE_ABS" ]; then
    echo "Error: File not found: $FINAL_OEM_FILE_ABS"
    exit 1
fi
FINAL_OEM_LOOP=$(find_loop_device "$FINAL_OEM_FILE_ABS") || { echo "Failed to create loop device for final OEM partition"; exit 1; }
mount -t ext2 "$FINAL_OEM_LOOP" "$MNT_FINAL_OEM" || { echo "Failed to mount final OEM partition"; losetup -d "$FINAL_OEM_LOOP" 2>/dev/null || true; exit 1; }

echo "Mounting final Recovery partition: $FINAL_RECOVERY_FILE_ABS"
if [ ! -f "$FINAL_RECOVERY_FILE_ABS" ]; then
    echo "Error: File not found: $FINAL_RECOVERY_FILE_ABS"
    exit 1
fi
FINAL_RECOVERY_LOOP=$(find_loop_device "$FINAL_RECOVERY_FILE_ABS") || { echo "Failed to create loop device for final Recovery partition"; exit 1; }
mount -t ext2 "$FINAL_RECOVERY_LOOP" "$MNT_FINAL_RECOVERY" || { echo "Failed to mount final Recovery partition"; losetup -d "$FINAL_RECOVERY_LOOP" 2>/dev/null || true; exit 1; }

# --- Copy Filesystems ---
echo "--- Copying Filesystem Data ---"
echo "Copying EFI partition..."
rsync -aHAX --info=progress2 "$MNT_INPUT_EFI/" "$MNT_FINAL_EFI/" || { echo "Failed to copy EFI partition"; exit 1; }
echo "EFI partition copied successfully"

echo "Copying Ubuntu root filesystem..."
# Use cp instead of rsync for better performance in container environment
echo "Starting Ubuntu filesystem copy (this may take a few minutes)..."
# Show progress by monitoring the destination directory size
(
    while true; do
        if [ -d "$MNT_FINAL_UBUNTU_ROOTFS" ]; then
            SIZE=$(du -sm "$MNT_FINAL_UBUNTU_ROOTFS" 2>/dev/null | cut -f1 || echo "0")
            echo "Ubuntu copy progress: ${SIZE}MB copied..."
        fi
        sleep 10
    done
) &
PROGRESS_PID=$!
PROGRESS_PIDS="$PROGRESS_PIDS $PROGRESS_PID"
cp -a "$MNT_UBUNTU_ROOT_IMG/." "$MNT_FINAL_UBUNTU_ROOTFS/" || { kill $PROGRESS_PID 2>/dev/null; echo "Failed to copy Ubuntu root filesystem"; exit 1; }
kill $PROGRESS_PID 2>/dev/null
wait $PROGRESS_PID 2>/dev/null || true
echo "Ubuntu root filesystem copied successfully"

echo "Copying OEM partition..."
rsync -aHAX --info=progress2 "$MNT_INPUT_OEM/" "$MNT_FINAL_OEM/" || { echo "Failed to copy OEM partition"; exit 1; }
echo "OEM partition copied successfully"

echo "Copying Recovery partition..."
# Use cp instead of rsync for better performance in container environment
echo "Starting Recovery partition copy (this may take a few minutes)..."
# Show progress by monitoring the destination directory size
(
    while true; do
        if [ -d "$MNT_FINAL_RECOVERY" ]; then
            SIZE=$(du -sm "$MNT_FINAL_RECOVERY" 2>/dev/null | cut -f1 || echo "0")
            echo "Recovery copy progress: ${SIZE}MB copied..."
        fi
        sleep 10
    done
) &
PROGRESS_PID=$!
PROGRESS_PIDS="$PROGRESS_PIDS $PROGRESS_PID"
cp -a "$MNT_INPUT_RECOVERY/." "$MNT_FINAL_RECOVERY/" || { kill $PROGRESS_PID 2>/dev/null; echo "Failed to copy Recovery partition"; exit 1; }
kill $PROGRESS_PID 2>/dev/null
wait $PROGRESS_PID 2>/dev/null || true
echo "Recovery partition copied successfully"

# --- Install curtin hooks ---
echo "--- Installing curtin hooks script ---"
mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/curtin"
cp "$CURTIN_HOOKS_SCRIPT" "$MNT_FINAL_UBUNTU_ROOTFS/curtin/"
chmod 750 "$MNT_FINAL_UBUNTU_ROOTFS/curtin/curtin-hooks"
echo "Curtin hooks script installed at /curtin/curtin-hooks with 750 permissions"

# Ensure curtin can detect this as a valid root filesystem
# Create marker files/directories that curtin looks for
echo "--- Creating curtin detection markers ---"
# Ensure /curtin directory exists and is visible with a file
if [ ! -f "$MNT_FINAL_UBUNTU_ROOTFS/curtin/.curtin-install-cache" ]; then
    touch "$MNT_FINAL_UBUNTU_ROOTFS/curtin/.curtin-install-cache"
fi

# Ensure standard Ubuntu structure exists (for snapd detection)
# Standard Ubuntu server images should have this, but ensure it exists
if [ ! -d "$MNT_FINAL_UBUNTU_ROOTFS/var/lib/snapd" ]; then
    mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/var/lib/snapd"
    echo "Created /var/lib/snapd directory for curtin detection"
fi

# Create a snaps directory if it doesn't exist (some curtin versions look for this)
if [ ! -d "$MNT_FINAL_UBUNTU_ROOTFS/snaps" ]; then
    mkdir -p "$MNT_FINAL_UBUNTU_ROOTFS/snaps"
    echo "Created /snaps directory for curtin detection"
fi

# Verify the structure is correct
echo "--- Verifying Ubuntu rootfs structure ---"
echo "Checking for curtin directory:"
ls -la "$MNT_FINAL_UBUNTU_ROOTFS/curtin/" || echo "Warning: /curtin directory not accessible"
echo "Checking for var/lib/snapd:"
ls -ld "$MNT_FINAL_UBUNTU_ROOTFS/var/lib/snapd" 2>/dev/null || echo "Warning: /var/lib/snapd not found"
echo "Root directory contents (first 20 items):"
ls -la "$MNT_FINAL_UBUNTU_ROOTFS/" | head -20 || true

echo "Curtin detection markers created and verified"

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

# --- Sync filesystems before unmounting ---
echo "--- Syncing filesystems ---"
sync
echo "Syncing Ubuntu rootfs..."
sync "$MNT_FINAL_UBUNTU_ROOTFS" || true
echo "Syncing EFI partition..."
sync "$MNT_FINAL_EFI" || true
echo "Syncing OEM partition..."
sync "$MNT_FINAL_OEM" || true
echo "Syncing Recovery partition..."
sync "$MNT_FINAL_RECOVERY" || true
sync

# --- Assemble Final Image ---
echo "--- Assembling final image ---"
echo "Writing EFI partition to final image..."
dd if="$FINAL_EFI_FILE" of="$FINAL_IMG" bs=1M seek=$COS_GRUB_SKIP_MB conv=notrunc || { echo "Failed to write EFI partition"; exit 1; }
sync
echo "EFI partition written successfully"

echo "Writing Ubuntu partition to final image..."
dd if="$FINAL_UBUNTU_FILE" of="$FINAL_IMG" bs=1M seek=$((COS_GRUB_SKIP_MB + COS_GRUB_SIZE_MB)) conv=notrunc || { echo "Failed to write Ubuntu partition"; exit 1; }
sync
echo "Ubuntu partition written successfully"

echo "Writing OEM partition to final image..."
dd if="$FINAL_OEM_FILE" of="$FINAL_IMG" bs=1M seek=$((COS_GRUB_SKIP_MB + COS_GRUB_SIZE_MB + UBUNTU_ROOT_SIZE_BYTES / 1048576)) conv=notrunc || { echo "Failed to write OEM partition"; exit 1; }
sync
echo "OEM partition written successfully"

echo "Writing Recovery partition to final image..."
dd if="$FINAL_RECOVERY_FILE" of="$FINAL_IMG" bs=1M seek=$((COS_GRUB_SKIP_MB + COS_GRUB_SIZE_MB + UBUNTU_ROOT_SIZE_BYTES / 1048576 + COS_OEM_SIZE_MB)) conv=notrunc || { echo "Failed to write Recovery partition"; exit 1; }
sync
echo "Recovery partition written successfully"

# Verify and potentially fix partition table after writing data
echo "--- Verifying partition table and filesystems ---"
parted -s "$FINAL_IMG" print || { echo "Warning: Could not verify partition table"; }

# Try to verify filesystems can be read and mounted
echo "--- Verifying filesystems can be read ---"
# Create a loop device for the final image to test mounting
FINAL_IMG_LOOP=$(losetup -f --show "$FINAL_IMG" 2>/dev/null || echo "")
if [ -n "$FINAL_IMG_LOOP" ]; then
    echo "Testing partition access on $FINAL_IMG_LOOP..."
    # Determine partition device naming (p2 for newer kernels, 2 for older)
    UBUNTU_PART=""
    if [ -e "${FINAL_IMG_LOOP}p2" ]; then
        UBUNTU_PART="${FINAL_IMG_LOOP}p2"
    elif [ -e "${FINAL_IMG_LOOP}2" ]; then
        UBUNTU_PART="${FINAL_IMG_LOOP}2"
    fi
    
    if [ -n "$UBUNTU_PART" ]; then
        echo "Testing ubuntu_rootfs partition ($UBUNTU_PART)..."
        PART_TYPE=$(file -s "$UBUNTU_PART" 2>/dev/null | grep -o "ext[0-9]" || echo "")
        PART_LABEL=$(blkid -L UBUNTU_ROOTFS 2>/dev/null || blkid -o value -s LABEL "$UBUNTU_PART" 2>/dev/null || echo "")
        echo "Partition type: $PART_TYPE"
        echo "Partition label: $PART_LABEL"
        
        # Try to mount it to verify it works
        TEST_MOUNT=$(mktemp -d)
        if mount -t ext4 "$UBUNTU_PART" "$TEST_MOUNT" 2>/dev/null; then
            echo "Successfully mounted ubuntu_rootfs partition"
            echo "Checking for curtin directory:"
            ls -la "$TEST_MOUNT/curtin/" 2>/dev/null || echo "Warning: /curtin not found in mounted partition"
            echo "Checking for var/lib/snapd:"
            ls -ld "$TEST_MOUNT/var/lib/snapd" 2>/dev/null || echo "Warning: /var/lib/snapd not found"
            umount "$TEST_MOUNT" 2>/dev/null || true
            rmdir "$TEST_MOUNT" 2>/dev/null || true
        else
            echo "Warning: Could not mount ubuntu_rootfs partition - this may cause curtin issues"
            rmdir "$TEST_MOUNT" 2>/dev/null || true
        fi
    else
        echo "Warning: Could not find ubuntu_rootfs partition device"
    fi
    losetup -d "$FINAL_IMG_LOOP" 2>/dev/null || true
fi
echo "Verification complete"

# --- Finalize ---
echo "--- Unmounting all mount points and cleaning up loop devices and temp directory ---"
umount -l "$MNT_INPUT_EFI" || true
umount -l "$MNT_INPUT_OEM" || true
umount -l "$MNT_INPUT_RECOVERY" || true
umount -l "$MNT_UBUNTU_ROOT_IMG" || true
umount -l "$MNT_FINAL_EFI" || true
umount -l "$MNT_FINAL_UBUNTU_ROOTFS" || true
umount -l "$MNT_FINAL_OEM" || true
umount -l "$MNT_FINAL_RECOVERY" || true

# Detach all loop devices
if [ -n "$INPUT_EFI_LOOP" ]; then losetup -d "$INPUT_EFI_LOOP" || true; fi
if [ -n "$INPUT_OEM_LOOP" ]; then losetup -d "$INPUT_OEM_LOOP" || true; fi
if [ -n "$INPUT_RECOVERY_LOOP" ]; then losetup -d "$INPUT_RECOVERY_LOOP" || true; fi
if [ -n "$FINAL_EFI_LOOP" ]; then losetup -d "$FINAL_EFI_LOOP" || true; fi
if [ -n "$FINAL_UBUNTU_LOOP" ]; then losetup -d "$FINAL_UBUNTU_LOOP" || true; fi
if [ -n "$FINAL_OEM_LOOP" ]; then losetup -d "$FINAL_OEM_LOOP" || true; fi
if [ -n "$FINAL_RECOVERY_LOOP" ]; then losetup -d "$FINAL_RECOVERY_LOOP" || true; fi
if [ -n "$UBUNTU_LOOP_DEV" ]; then losetup -d "$UBUNTU_LOOP_DEV" || true; fi
echo "--- Copying final image to original directory... ---"
cp "$FINAL_IMG" "$ORIG_DIR/" || { echo "Failed to copy final image"; exit 1; }
echo "Final image copied successfully"

# Check final image size
FINAL_SIZE=$(du -h "$ORIG_DIR/$FINAL_IMG" | cut -f1)
echo "Final image size: $FINAL_SIZE"

# Cleanup mount points (but keep WORKDIR until after file copy)
rm -rf "$MNT_INPUT_EFI" "$MNT_INPUT_OEM" "$MNT_INPUT_RECOVERY" "$MNT_UBUNTU_ROOT_IMG" "$MNT_FINAL_EFI" "$MNT_FINAL_UBUNTU_ROOTFS" "$MNT_FINAL_OEM" "$MNT_FINAL_RECOVERY"

echo ""
echo "✅ Composite image created successfully: $ORIG_DIR/$FINAL_IMG"
echo "Final image location: $ORIG_DIR/$FINAL_IMG"
echo "You can now upload this raw image to your deployment system."
echo "📋 Cloud-init userdata processing script has been integrated - it will:"
echo "   • Run once after cloud-init processes userdata"
echo "   • Copy userdata to COS_OEM partition as userdata.yaml" 
echo "   • Set grubenv to boot recovery mode"
echo "   • Reboot the system"

# Mark cleanup as done and exit cleanly
# Kill any remaining background progress monitoring processes
for pid in $PROGRESS_PIDS; do
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
done

CLEANUP_DONE=true
rm -rf "$WORKDIR"
exit 0

