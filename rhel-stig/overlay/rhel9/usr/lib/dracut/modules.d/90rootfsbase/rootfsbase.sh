#!/bin/sh
# Early initramfs script to create /run/rootfsbase and /run/overlayfs for overlayfs
# This runs in pre-mount hook (priority 10) before overlayfs tries to mount
# Works in vSphere, VMware, and other virtualization environments
# Both paths may be needed depending on dracut-live version

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

# Create both /run/rootfsbase and /run/overlayfs directories
# Different dracut-live versions may use different paths
# Try multiple times in case /run is being mounted asynchronously
for i in 1 2 3; do
    if [ ! -d /run/rootfsbase ]; then
        mkdir -p /run/rootfsbase 2>/dev/null && break || sleep 0.1
    fi
done
for i in 1 2 3; do
    if [ ! -d /run/overlayfs ]; then
        mkdir -p /run/overlayfs 2>/dev/null && break || sleep 0.1
    fi
done

# Verify they were created and set permissions
if [ -d /run/rootfsbase ]; then
    chmod 755 /run/rootfsbase
    echo "rootfsbase: Created /run/rootfsbase for overlayfs"
fi
if [ -d /run/overlayfs ]; then
    chmod 755 /run/overlayfs
    echo "rootfsbase: Created /run/overlayfs for overlayfs"
fi

# Last resort: try creating in initramfs root if /run isn't available
[ -d /run/rootfsbase ] || mkdir -p /run/rootfsbase 2>/dev/null || true
[ -d /run/overlayfs ] || mkdir -p /run/overlayfs 2>/dev/null || true
