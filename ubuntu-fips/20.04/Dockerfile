
# Kairos init image
FROM quay.io/kairos/kairos-init:v0.8.12 AS kairos-init

# Base ubuntu image (focal)
FROM ubuntu:focal AS base

ARG KAIROS_VERSION=v4.0.3

# Don't get asked while running apt commands
ENV DEBIAN_FRONTEND=noninteractive

# NOTE: --fips is NOT passed here. Unlike RHEL (where subscription-manager enables FIPS repos
# before this step), Ubuntu FIPS packages require Ubuntu PRO, which is only attached in the
# apt-get install block below. kairos-init would fail with "FIPS is not supported on Ubuntu
# without a PRO account and extra packages" if --fips were used at this stage.
RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install --version "${KAIROS_VERSION}"

RUN apt-get remove -y linux-base linux-image-generic-hwe-20.04 && apt-get autoremove -y \
    && dpkg -l 'linux-*' | awk '/^(ii|rc)/ && $2 !~ /fips/ {print $2}' | xargs -r apt-get purge -y

## THIS comes from the Ubuntu documentation: https://canonical-ubuntu-pro-client.readthedocs-hosted.com/en/latest/tutorials/create_a_fips_docker_image.html
## I've just added "linux-image-fips" in the package list
RUN --mount=type=secret,id=pro-attach-config \
    apt-get update \
    && apt-get install --no-install-recommends -y ubuntu-advantage-tools ca-certificates \
    && pro attach --attach-config /run/secrets/pro-attach-config \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    openssl \
    libssl1.1 \
    libssl1.1-hmac \
    libgcrypt20 \
    libgcrypt20-hmac \
    strongswan \
    strongswan-hmac \
    openssh-client \
    openssh-server \
    linux-image-fips \
    linux-headers-fips \
    shim-signed \
    conntrack \
    console-data \
    coreutils \
    cryptsetup \
    curl \
    debianutils \
    dmsetup \
    dosfstools \
    e2fsprogs \
    efibootmgr \
    file \
    fuse \
    gawk \
    gdisk \
    grub2 \
    grub2-common \
    grub-efi-amd64-bin \
    grub-efi-amd64-signed \
    grub-pc-bin \
    haveged \
    iproute2 \
    iptables \
    isc-dhcp-common \
    isc-dhcp-client \
    jq \
    kbd \
    krb5-locales \
    lldpd \
    lvm2 \
    mdadm \
    nano \
    nbd-client \
    ncurses-term \
    neovim \
    networkd-dispatcher \
    nfs-common \
    open-iscsi \
    openssh-server \
    open-vm-tools \
    os-prober \
    packagekit-tools \
    parted \
    patch \
    policykit-1 \
    publicsuffix \
    qemu-guest-agent \
    rsync \
    shared-mime-info \
    snmpd \
    squashfs-tools \
    sudo \
    systemd \
    systemd-timesyncd \
    thermald \
    ubuntu-advantage-tools \
    xdg-user-dirs \
    xxd \
    xz-utils \
    zerofree \
    zfsutils-linux \
    zstd \
    cloud-guest-utils \
    cracklib-runtime \
    && apt-get remove -y unattended-upgrades && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && pro detach --assume-yes

COPY dracut-broken-iscsi-ubuntu-20.patch /
RUN cd /usr/lib/dracut/modules.d/95iscsi && patch < /dracut-broken-iscsi-ubuntu-20.patch && rm -rf /dracut-broken-iscsi-ubuntu-20.patch

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

# Copy the custom dracut modules.fips that includes 2 missing modules
COPY modules.fips /tmp/modules.fips
RUN kernel=$(ls /lib/modules | grep fips | head -n1) && mv /tmp/modules.fips /lib/modules/${kernel}/modules.fips

# --fips is passed here (not at install stage) because Ubuntu PRO has been attached and all
# FIPS packages (linux-image-fips, openssl, libssl1.1-hmac, etc.) are already installed above.
# This sets KAIROS_FIPS="true" in /etc/kairos-release so the image is correctly identified
# as a FIPS build. fips=1 on the kernel cmdline must still be set via cloud-config extra_cmdline.
RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init --fips --version "${KAIROS_VERSION}"

# Symlink kernel HMAC
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac
