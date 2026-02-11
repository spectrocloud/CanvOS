#!/bin/sh
# Early initramfs script to mount /run as tmpfs and create required directories
# This runs in initqueue, pre-trigger, cmdline, and pre-mount hooks (priority 5-10)
# Works in vSphere, VMware, and other virtualization environments
# The error is: overlayfs: failed to resolve '/run/rootfs': -2 or '/run/rootfsbase': -2

# Mount /run as tmpfs if it doesn't exist or isn't mounted
# /run may not exist during early initramfs boot
if [ ! -d /run ]; then
    mkdir -p /run 2>/dev/null || true
fi

# Mount /run as tmpfs if not already mounted
# This must happen BEFORE systemd-journald tries to start
if ! mountpoint -q /run 2>/dev/null; then
    mount -t tmpfs -o mode=0755,size=10% tmpfs /run 2>/dev/null || {
        # If mount fails, at least ensure directory exists
        mkdir -p /run 2>/dev/null || true
    }
fi

# Create /run/systemd/journal directory structure FIRST
# This must exist before systemd-journald starts or services will retry and delay
mkdir -p /run/systemd/journal 2>/dev/null || true
chmod 755 /run/systemd 2>/dev/null || true
chmod 1777 /run/systemd/journal 2>/dev/null || true  # 1777 allows journal socket creation

# Create both /run/rootfs and /run/rootfsbase directories
# Different dracut-live versions may use different paths
mkdir -p /run/rootfs 2>/dev/null || true
mkdir -p /run/rootfsbase 2>/dev/null || true
chmod 755 /run/rootfs 2>/dev/null || true
chmod 755 /run/rootfsbase 2>/dev/null || true

# Log to kernel log since journal may not be available yet
echo "rootfsbase: Mounted /run and created required directories" > /dev/kmsg 2>/dev/null || true
