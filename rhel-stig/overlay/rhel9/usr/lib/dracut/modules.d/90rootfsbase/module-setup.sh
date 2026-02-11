#!/bin/bash
# Dracut module to ensure /run/rootfsbase exists for overlayfs
# This module runs early in initramfs to create the directory before overlayfs mounts
# Works in vSphere, VMware, and other virtualization environments

check() {
    # Always include this module
    return 0
}

depends() {
    # Don't depend on systemd - we need to run BEFORE systemd sets up /run
    # This ensures /run and /run/systemd/journal exist before systemd-journald starts
    # If we depend on systemd, we might run too late
    return 0
}

install() {
    # Install the script that creates /run/rootfsbase and /run/systemd/journal
    # Run in multiple hooks with highest priority (1 = earliest) to ensure it happens FIRST:
    # - initqueue: runs very early, before most services (priority 1 = earliest)
    # - pre-trigger: runs before udev trigger (priority 1 = earliest)
    # - cmdline: runs during cmdline parsing (priority 1 = earliest)
    # - pre-mount: runs before rootfs mount (priority 1 = earliest)
    # Lower priority numbers run earlier, so 1 ensures we run before other modules
    inst_hook initqueue 1 "$moddir/rootfsbase.sh"
    inst_hook pre-trigger 1 "$moddir/rootfsbase.sh"
    inst_hook cmdline 1 "$moddir/rootfsbase.sh"
    inst_hook pre-mount 1 "$moddir/rootfsbase.sh"
}
