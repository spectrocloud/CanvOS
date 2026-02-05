#!/bin/sh
# Early initramfs script to create /run/rootfsbase for overlayfs
# This runs in pre-mount hook (priority 10) before overlayfs tries to mount

# Ensure /run exists (it should be a tmpfs mount, but create it if needed)
if [ ! -d /run ]; then
    mkdir -p /run
fi

# Create /run/rootfsbase directory required by overlayfs
# This MUST exist before dracut-live tries to set up overlayfs
if [ ! -d /run/rootfsbase ]; then
    mkdir -p /run/rootfsbase
    chmod 755 /run/rootfsbase
    echo "Created /run/rootfsbase for overlayfs"
fi
