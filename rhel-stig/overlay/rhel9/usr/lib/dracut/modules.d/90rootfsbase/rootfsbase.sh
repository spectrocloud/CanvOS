#!/bin/sh
# Early initramfs script to create /run/overlayfs for overlayfs
# This runs in pre-mount hook (priority 10) before overlayfs tries to mount
# Works in vSphere, VMware, and other virtualization environments
# The actual path needed is /run/overlayfs (not /run/rootfsbase)

# Ensure /run exists - it should be a tmpfs mount, but create it if needed
# In some virtualization environments, /run might not be mounted yet
if [ ! -d /run ]; then
    mkdir -p /run
    # If /run is not a mount point, ensure it's accessible
    if ! mountpoint -q /run 2>/dev/null; then
        # /run might not be mounted yet, but we can still create subdirectories
        # The directory will be created in the root filesystem temporarily
        mkdir -p /run
    fi
fi

# Create /run/overlayfs directory required by overlayfs (rd.live.overlay.overlayfs)
# This MUST exist before dracut-live tries to set up overlayfs
# Try multiple times in case /run is being mounted asynchronously
for i in 1 2 3; do
    if [ ! -d /run/overlayfs ]; then
        mkdir -p /run/overlayfs 2>/dev/null && break || sleep 0.1
    fi
done

# Verify it was created and set permissions
if [ -d /run/overlayfs ]; then
    chmod 755 /run/overlayfs
    echo "rootfsbase: Created /run/overlayfs for overlayfs"
else
    # Last resort: try creating in initramfs root if /run isn't available
    mkdir -p /run/overlayfs
    chmod 755 /run/overlayfs
    echo "rootfsbase: Created /run/overlayfs (fallback)"
fi
