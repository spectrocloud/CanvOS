#!/bin/bash
# Dracut module to ensure /run/rootfsbase exists for overlayfs
# This module runs early in initramfs to create the directory before overlayfs mounts
# Works in vSphere, VMware, and other virtualization environments

check() {
    # Always include this module
    return 0
}

depends() {
    # Depend on systemd if available, but don't require it
    # This ensures we run after systemd sets up /run if present
    if dracut_module_included "systemd"; then
        echo systemd
    fi
    return 0
}

install() {
    # Install the script that creates /run/rootfsbase
    # Use pre-mount hook with priority 10 to run early, before overlayfs mounts
    # Also install in cmdline hook as a backup (runs even earlier)
    inst_hook cmdline 10 "$moddir/rootfsbase.sh"
    inst_hook pre-mount 10 "$moddir/rootfsbase.sh"
}
