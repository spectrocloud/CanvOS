#!/bin/sh
# Early initramfs script to create /run/rootfsbase for overlayfs
# This runs in pre-mount hook (priority 10) before overlayfs tries to mount
# Works in vSphere, VMware, and other virtualization environments

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

# Create /run/rootfsbase directory required by overlayfs
# This MUST exist before dracut-live tries to set up overlayfs
# Try multiple times in case /run is being mounted asynchronously
for i in 1 2 3; do
    if [ ! -d /run/rootfsbase ]; then
        mkdir -p /run/rootfsbase 2>/dev/null && break || sleep 0.1
    fi
done

# Verify it was created and set permissions
if [ -d /run/rootfsbase ]; then
    chmod 755 /run/rootfsbase
    echo "rootfsbase: Created /run/rootfsbase for overlayfs"
else
    # Last resort: try creating in initramfs root if /run isn't available
    mkdir -p /run/rootfsbase
    chmod 755 /run/rootfsbase
    echo "rootfsbase: Created /run/rootfsbase (fallback)"
fi
