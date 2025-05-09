# This file is auto-generated with the command: earthly +kairos-dockerfile --FAMILY=ubuntu
###############################################################
####                           ARGS                        ####
###############################################################
ARG FAMILY=ubuntu
# Currently supported flavors are:
#   - ubuntu
ARG FLAVOR
#   - 20.04
#   - 22.04
#   - 23.04
ARG FLAVOR_RELEASE
# Currently supported models are:
#   - generic
#   - rpi4
#   - rpi3
ARG MODEL=generic
ARG BASE_IMAGE
ARG VARIANT
ARG VERSION
ARG FRAMEWORK_VERSION=v2.11.7
# Not to be confused with the concept of MODEL, this is either fips or generic
ARG SECURITY_PROFILE=generic
# TARGETARCH is used to determine the architecture of the image
# it is already set by Docker so it doesn't need to be defined here

###############################################################
####                     Upstream Images                   ####
###############################################################
FROM ${BASE_IMAGE} AS ubuntu-23.04-upstream

FROM ${BASE_IMAGE} AS ubuntu-20.04-upstream

FROM ${BASE_IMAGE} AS ubuntu-22.04-upstream


###############################################################
####                Pre-Process Common to All              ####
###############################################################
FROM ${FLAVOR}-${FLAVOR_RELEASE}-upstream AS common
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    gnupg \
    software-properties-common \
  && add-apt-repository ppa:oibaf/test \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    conntrack \
    console-data \
    cloud-guest-utils \
    coreutils \
    cryptsetup \
    curl \
    debianutils \
    dosfstools \
    dracut \
    dracut-network \
    e2fsprogs \
    fdisk \
    file \
    gawk \
    gdisk \
    grub2-common \
    haveged \
    iproute2 \
    iptables \
    iputils-ping \
    jq \
    kbd \
    krb5-locales \
    less \
    lldpd \
    lvm2 \
    nano \
    nbd-client \
    neovim \
    nohang \
    open-iscsi \
    open-vm-tools \
    openssh-server \
    parted \
    rsync \
    snmpd \
    squashfs-tools \
    sudo \
    systemd \
    systemd-timesyncd \
    tar \
    ubuntu-advantage-tools \
    xz-utils \
    zstd \
    && apt-get remove -y unattended-upgrades && apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################
####           Common to a Single Architecture             ####
###############################################################

FROM common AS amd64
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    dmsetup \
    efibootmgr \
    grub2 \
    grub-efi-amd64-bin \
    grub-efi-amd64-signed \
    grub-pc-bin \
    isc-dhcp-common \
    mdadm \
    ncurses-term \
    networkd-dispatcher \
    nfs-common \
    os-prober \
    packagekit-tools \
    publicsuffix \
    shared-mime-info \
    thermald \
    xdg-user-dirs \
    xxd \
    zerofree \
    zfsutils-linux \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM common AS arm64
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    grub-efi-arm64 \
    grub-efi-arm64-bin \
    grub-efi-arm64-signed \
    keyutils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

###############################################################
####            Common to an Arch and Flavor               ####
###############################################################
FROM ${TARGETARCH} AS base-ubuntu-20.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    file \
    fuse \
    patch \
    policykit-1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM ${TARGETARCH} AS base-ubuntu-22.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    dracut-live \
    firmware-sof-signed \
    fuse3 \
    pigz \
    polkitd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM base-ubuntu-20.04 AS amd64-base-ubuntu-20.04
# If a kernel is already installed, don't try to install it again, this way the base image can
# be non-hwe for older releases
RUN apt-get update
RUN [ -z "$(ls -A /lib/modules/)" ] && apt-get install -y --no-install-recommends \
    linux-image-generic-hwe-20.04 || true
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

FROM base-ubuntu-22.04 AS amd64-base-ubuntu-22.04
RUN apt-get update
# If a kernel is already installed, don't try to install it again, this way the base image can
# be non-hwe for older releases
RUN [ -z "$(ls -A /lib/modules)" ] && apt-get install -y --no-install-recommends \
    linux-image-generic-hwe-22.04 || true
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

FROM amd64-base-ubuntu-22.04 AS amd64-ubuntu-23.04
FROM amd64-base-ubuntu-22.04 AS amd64-ubuntu-22.04
FROM amd64-base-ubuntu-20.04 AS amd64-ubuntu-20.04

FROM base-ubuntu-22.04 AS arm64-ubuntu-23.04
FROM base-ubuntu-22.04 AS arm64-ubuntu-22.04
FROM base-ubuntu-20.04 AS arm64-ubuntu-20.04

###############################################################
####               Common to a Single Model                ####
###############################################################
FROM ${TARGETARCH}-${FLAVOR}-${FLAVOR_RELEASE} AS generic
RUN apt-get update && apt-get install -y --no-install-recommends \
    linux-base \
    qemu-guest-agent \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM arm64-${FLAVOR}-${FLAVOR_RELEASE} AS rpicommon
RUN apt-get update && apt-get install -y --no-install-recommends \
    linux-raspi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY rpi/config.txt /boot/config.txt

FROM rpicommon AS ubuntu-20.04-rpi
RUN apt-get update && apt-get install -y --no-install-recommends \
    linux-firmware-raspi2 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM rpicommon AS ubuntu-23.04-rpi
RUN apt-get update && apt-get install -y --no-install-recommends \
    linux-firmware-raspi \
    linux-modules-extra-raspi \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM generic AS amd64-ubuntu-23.04-generic
FROM generic AS amd64-ubuntu-22.04-generic
FROM generic AS amd64-ubuntu-20.04-generic
FROM generic AS arm64-ubuntu-23.04-generic
FROM ubuntu-23.04-rpi AS arm64-ubuntu-23.04-rpi3
FROM ubuntu-23.04-rpi AS arm64-ubuntu-23.04-rpi4
FROM ubuntu-23.04-rpi AS arm64-ubuntu-22.04-rpi3
FROM ubuntu-23.04-rpi AS arm64-ubuntu-22.04-rpi4
FROM ubuntu-20.04-rpi AS arm64-ubuntu-20.04-rpi3
FROM ubuntu-20.04-rpi AS arm64-ubuntu-20.04-rpi4
FROM ubuntu-20.04-upstream AS arm64-ubuntu-20.04-nvidia-jetson-agx-orin

###############################################################
####                Common to a Single Flavor              ####
###############################################################
FROM ${TARGETARCH}-${FLAVOR}-${FLAVOR_RELEASE}-${MODEL} AS ubuntu-23.04
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    dbus-user-session \
    pkg-config \
    systemd-hwe-hwdb \
    systemd-resolved \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

FROM ${TARGETARCH}-${FLAVOR}-${FLAVOR_RELEASE}-${MODEL} AS ubuntu-22.04
RUN apt-get update
# If the generic kernel is installed we don't want to install HWE related packages
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-cache search linux-image-generic | grep hwe &> /dev/null && apt-get install -y --no-install-recommends \
    systemd-hwe-hwdb
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

FROM ${TARGETARCH}-${FLAVOR}-${FLAVOR_RELEASE}-${MODEL} AS ubuntu-20.04

###############################################################
####               Post-Process Common to All              ####
###############################################################
FROM ${FLAVOR}-${FLAVOR_RELEASE} AS all

# compress firmware
RUN find /usr/lib/firmware -type f -execdir zstd --rm -9 {} \+
# compress modules
RUN find /usr/lib/modules -type f -name "*.ko" -execdir zstd --rm -9 {} \+

RUN systemctl enable systemd-networkd
RUN systemctl enable ssh

# Fixup sudo perms
RUN chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo

RUN journalctl --vacuum-size=1K && rm /etc/machine-id && rm /var/lib/dbus/machine-id && rm /etc/hostname

FROM --platform="linux/${TARGETARCH}" quay.io/kairos/framework:${FRAMEWORK_VERSION}_${SECURITY_PROFILE} AS framework

FROM all AS base-kairos

# Symlinks to make elemental installer work
RUN ORIG=/usr/sbin/grub-install; DEST=/usr/sbin/grub2-install; [ -e $ORIG ] && [ ! -e $DEST ] && ln -s $ORIG $DEST || true
RUN ORIG=/usr/bin/grub-editenv; DEST=/usr/sbin/grub2-editenv; [ -e $ORIG ] && [ ! -e $DEST ] && ln -s $ORIG $DEST || true

# Originally done in Earthly
COPY --from=framework / /

RUN rm -rf /etc/ssh/ssh_host_*

COPY naming.sh /usr/local/bin/naming.sh
COPY which-init.sh /usr/local/bin/which-init.sh

RUN sed -i -n '/KAIROS_/!p' /etc/os-release

# need to be defined after FROM for them to be replaced in the RUN bellow
ARG FLAVOR
ARG FLAVOR_RELEASE
ARG VARIANT
ARG OS_ID=kairos
ARG HOME_URL="https://github.com/kairos-io/kairos"
ARG BUG_REPORT_URL="https://github.com/kairos-io/kairos/issues"
ARG GITHUB_REPO="kairos-io/kairos"
# TODO: merge these
ARG VERSION
ARG FAMILY
ARG MODEL
ARG REGISTRY_AND_ORG="quay.io/kairos"
ARG K3S_VERSION
ARG TARGETARCH
ARG OS_NAME=kairos-${VARIANT}-${FLAVOR}-${FLAVOR_RELEASE}
ENV KAIROS_VERSION="${VERSION}${K3S_VERSION:+-k3s$K3S_VERSION}"
ENV OS_VERSION=${KAIROS_VERSION}
ENV OS_LABEL=${KAIROS_VERSION}
RUN OS_LABEL=$(naming.sh container_artifact_label) \
    OS_REPO=$(naming.sh container_artifact_repo) \
    ARTIFACT=$(naming.sh bootable_artifact_name) \
    envsubst >>/etc/os-release </usr/lib/os-release.tmpl
RUN naming.sh container_artifact_name > /IMAGE

RUN rm -rf /etc/machine-id

FROM base-kairos AS kairos-core

FROM base-kairos AS kairos-standard
ARG K3S_VERSION
LABEL io.kairos.k3s_version="${K3S_VERSION}"
RUN luet install -y system/provider-kairos
RUN luet install -y "k8s/k3s-$(which-init.sh)@${K3S_VERSION}" utils/edgevpn utils/k9s utils/nerdctl container/kubectl utils/kube-vip

FROM kairos-${VARIANT} AS kairos-final
ARG BASE_IMAGE
ARG VARIANT
ARG FAMILY
ARG FLAVOR
ARG FLAVOR_RELEASE
ARG MODEL
ARG VERSION
ARG FRAMEWORK_VERSION
ARG SECURITY_PROFILE
LABEL org.opencontainers.image.authors="Kairos Maintainers <team@kairos.io>"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.url="https://github.com/kairos-io/kairos"
LABEL org.opencontainers.image.source="https://github.com/kairos-io/kairos.git"
LABEL io.kairos.base_image="${BASE_IMAGE}"
LABEL io.kairos.variant="${VARIANT}"
LABEL io.kairos.family="${FAMILY}"
LABEL io.kairos.flavor="${FLAVOR}"
LABEL io.kairos.flavor_release="${FLAVOR_RELEASE}"
LABEL io.kairos.model="${MODEL}"
LABEL io.kairos.version="${VERSION}"
LABEL io.kairos.framework-version="${FRAMEWORK_VERSION}"
LABEL io.kairos.security-profile="${SECURITY_PROFILE}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN luet database get-all-installed --output /etc/kairos/versions.yaml

# TODO what about caches?
RUN kernel=$(ls /lib/modules | head -n1) && depmod -a "${kernel}"
# Regenerate initrd if necessary, proper config files with immucore and custom initrd should already be in there installed by framework
# for systemd distros
RUN if [ -f "/usr/bin/dracut" ]; then \
      kernel=$(ls /lib/modules | head -n1) && \
      dracut -f "/boot/initrd-${kernel}" "${kernel}" && \
      ln -sf "initrd-${kernel}" /boot/initrd; \
    fi
# for alpine (openrc based)
RUN if [ -f "/sbin/mkinitfs" ]; then \
      kernel=$(ls /lib/modules | head -n1) && \
      mkinitfs -o /boot/initrd "${kernel}"; \
    fi

# symlink kernel to /boot/vmlinuz
RUN kernel=$(ls /boot/vmlinuz-* 2>/dev/null | head -n1) && if [ -e "$kernel" ]; then ln -sf "$kernel" /boot/vmlinuz; fi || true
RUN kernel=$(ls /boot/Image-* 2>/dev/null | head -n1) && if [ -e "$kernel" ]; then ln -sf "$kernel" /boot/vmlinuz; fi || true

# this is generally present on rhel based systems, but it doesn't hurt to remove in any case
RUN rm -rf /boot/initramfs-* || true

RUN rm -rf /tmp/*
RUN luet cleanup
RUN rm -rf /var/luet