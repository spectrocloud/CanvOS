#!/bin/bash
# Dracut module to ensure /run/rootfsbase exists for overlayfs
# This module runs early in initramfs to create the directory before overlayfs mounts
# Works in vSphere, VMware, and other virtualization environments

check() {
    # Always include this module
    return 0
}

depends() {
    # Depend on systemd - let systemd set up /run properly first
    # We just need to create mountpoints before overlay assembly
    dracut_module_included "systemd" && echo systemd
    return 0
}

install() {
    # Install the script that creates /run/rootfsbase
    # Run at pre-mount hook with priority 10 (after systemd has set up /run)
    # This is early enough to create mount points before overlay assembly,
    # but late enough that systemd has already established /run sanely
    inst_hook pre-mount 10 "$moddir/rootfsbase.sh"
}
