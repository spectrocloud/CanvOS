# Slims the UKI by dropping AMD/NVIDIA GPU firmware from the monolithic
# linux-firmware package until Ubuntu finishes splitting it:
#   https://bugs.launchpad.net/ubuntu/+source/linux-firmware/+bug/1958518
#
# GPU nodes that need those blobs should either:
#   - build with --build-arg KEEP_GPU_FIRMWARE=true, or
#   - enable INSTALL_NVIDIA_GPU_DRIVERS / INSTALL_AMD_GPU_DRIVERS in the
#     Earthfile (air-gapped GPU Operator path), or
#   - ship those blobs as a signed sysext (Kairos Trusted Boot pattern).
#
ARG KAIROS_INIT_VERSION=v0.16.3
ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION}

FROM ${KAIROS_INIT_IMAGE} AS kairos-init

FROM ubuntu:24.04
ARG VERSION=v4.1.2
ARG MODEL=generic
ARG KEEP_GPU_FIRMWARE=false


RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install -m "${MODEL}" -t true --version "${VERSION}"


# QEMU/KVM guest agent for VMO integration (IP reporting, graceful
# shutdown, etc.).
RUN DEBIAN_FRONTEND=noninteractive && apt-get update \
    && apt-get install -y --no-install-recommends qemu-guest-agent \
    && systemctl enable qemu-guest-agent.service \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Trim AMD/NVIDIA GPU firmware (and matching in-tree DRM modules) by default.
#
# Why: UKI packs the full rootfs into the PE .initrd. Ubuntu's linux-firmware
# is still a monolith (~0.5 GiB+); nvidia + amdgpu blobs are among the
# largest vendor trees and push many UKIs over the ~1 GiB UEFI load limit.
# Upstream is splitting the package (https://bugs.launchpad.net/ubuntu/+source/linux-firmware/+bug/1958518); until that lands in 24.04, delete the GPU trees after -s install and before -s init so dracut never packs them.
COPY trim-gpu-firmware.sh /tmp/trim-gpu-firmware.sh
RUN chmod 755 /tmp/trim-gpu-firmware.sh \
    && KEEP_GPU_FIRMWARE="${KEEP_GPU_FIRMWARE}" /tmp/trim-gpu-firmware.sh \
    && rm -f /tmp/trim-gpu-firmware.sh


RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init -m "${MODEL}" -t true --version "${VERSION}"
