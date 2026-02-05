#!/bin/bash
# Dracut module to ensure /run/rootfsbase exists for overlayfs
# This module runs early in initramfs to create the directory before overlayfs mounts

check() {
    # Always include this module
    return 0
}

depends() {
    # No dependencies - we want to run as early as possible
    return 0
}

install() {
    # Install the script that creates /run/rootfsbase
    # Use pre-mount hook with priority 10 to run early, before overlayfs mounts
    inst_hook pre-mount 10 "$moddir/rootfsbase.sh"
}
