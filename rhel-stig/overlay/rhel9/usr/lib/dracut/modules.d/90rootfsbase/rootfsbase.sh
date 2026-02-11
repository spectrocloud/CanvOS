#!/bin/sh
# Minimal: do not mount /run, do not touch systemd journal dirs.
# Just ensure overlay mountpoints exist if /run exists.
# This runs at pre-mount hook (priority 10) after systemd has set up /run

[ -d /run ] || mkdir -p /run 2>/dev/null || true

mkdir -p /run/rootfs /run/rootfsbase 2>/dev/null || true
chmod 755 /run/rootfs /run/rootfsbase 2>/dev/null || true

echo "rootfsbase: ensured /run/rootfs{,base}" > /dev/kmsg 2>/dev/null || true
