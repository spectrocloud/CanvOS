#!/bin/bash

# Screenshot capability:
# https://unix.stackexchange.com/a/476617

if [ ! -e disk.img ]; then
    qemu-img create -f qcow2 disk.img 60g
fi
 
#    -nic bridge,br=br0,model=virtio-net-pci \
qemu-system-x86_64 \
    -enable-kvm \
    -cpu "${CPU:=host}" \
    -nographic \
    -spice port=9000,addr=127.0.0.1,disable-ticketing=yes \
    -m ${MEMORY:=10096} \
    -smp ${CORES:=5} \
    -monitor unix:/tmp/qemu-monitor.sock,server=on,wait=off \
    -serial mon:stdio \
    -rtc base=utc,clock=rt \
    -chardev socket,path=qga.sock,server=on,wait=off,id=qga0 \
    -device virtio-serial \
    -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    -drive if=virtio,media=disk,file=disk.img \
    -drive if=ide,media=cdrom,file="${1}"
