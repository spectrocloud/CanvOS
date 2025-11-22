
# Kairos init image
FROM quay.io/kairos/kairos-init:v0.5.20 AS kairos-init

# Base ubuntu image (focal)
FROM ubuntu:focal AS base

ARG KAIROS_VERSION=v3.5.7

# Don't get asked while running apt commands
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install --version "${KAIROS_VERSION}"

RUN apt-get remove -y linux-base linux-image-generic-hwe-20.04 && apt-get autoremove -y

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
    dracut \
    dracut-network \
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
    && apt-get remove -y unattended-upgrades && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && pro detach --assume-yes

COPY dracut-broken-iscsi-ubuntu-20.patch /
RUN cd /usr/lib/dracut/modules.d/95iscsi && patch < /dracut-broken-iscsi-ubuntu-20.patch && rm -rf /dracut-broken-iscsi-ubuntu-20.patch

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init --version "${KAIROS_VERSION}"

# Symlink kernel HMAC
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac
