#!/bin/sh
# Early initramfs script to mount /run as tmpfs and create required directories
# This runs in cmdline and pre-mount hooks (priority 10) before overlayfs tries to mount
# Works in vSphere, VMware, and other virtualization environments
# The error is: overlayfs: failed to resolve '/run/rootfs': -2 or '/run/rootfsbase': -2

# Mount /run as tmpfs if it doesn't exist or isn't mounted
# /run may not exist during early initramfs boot
if [ ! -d /run ]; then
    mkdir -p /run 2>/dev/null || true
fi

# Mount /run as tmpfs if not already mounted
if ! mountpoint -q /run 2>/dev/null; then
    mount -t tmpfs -o mode=0755 tmpfs /run 2>/dev/null || {
        # If mount fails, at least ensure directory exists
        mkdir -p /run 2>/dev/null || true
    }
fi

# Create both /run/rootfs and /run/rootfsbase directories
# Different dracut-live versions may use different paths
mkdir -p /run/rootfs 2>/dev/null || true
mkdir -p /run/rootfsbase 2>/dev/null || true
chmod 755 /run/rootfs 2>/dev/null || true
chmod 755 /run/rootfsbase 2>/dev/null || true

echo "rootfsbase: Mounted /run and created /run/rootfs and /run/rootfsbase"
