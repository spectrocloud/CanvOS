
# Kairos framework packages for ubuntu fips
# FROM gcr.io/spectro-images-public/kairos/framework:v2.11.7-fips as kairos-fips
FROM quay.io/kairos/framework:v2.11.7-fips as kairos-fips

# Base ubuntu image (focal)
FROM ubuntu:focal as base

# Generate os-release file
FROM quay.io/kairos/osbuilder-tools:v0.200.11 as osbuilder
RUN zypper install -y gettext && zypper clean
RUN mkdir /workspace
COPY --from=base /etc/os-release /workspace/os-release
# You should change the following values according to your own versioning and other details
RUN OS_NAME=kairos-core-ubuntu-fips \
  OS_VERSION=v3.1.3 \
  OS_ID="ubuntu" \
  BUG_REPORT_URL="https://github.com/spectrocloud/ubuntu-fips-edge/issues" \
  HOME_URL="https://github.com/spectrocloud/ubuntu-fips-edge" \
  OS_REPO="gcr.io/spectro-images-public/ubuntu-focal-fips" \
  OS_LABEL="20.04" \
  GITHUB_REPO="https://github.com/spectrocloud/ubuntu-fips-edge" \
  VARIANT="fips" \
  FLAVOR="ubuntu" \
  /update-os-release.sh

# Build the custom ubuntu image
FROM base

# Don't get asked while running apt commands
ENV DEBIAN_FRONTEND=noninteractive

## THIS comes from the Ubuntu documentation: https://canonical-ubuntu-pro-client.readthedocs-hosted.com/en/latest/tutorials/create_a_fips_docker_image.html
## I've just added "linux-image-fips" in the package list
RUN --mount=type=secret,id=pro-attach-config \
    apt-get update \
    && apt-get install --no-install-recommends -y ubuntu-advantage-tools ca-certificates \
    && pro attach --attach-config /run/secrets/pro-attach-config \
    && apt-get upgrade -y \
    && apt-get install -y openssl libssl1.1 libssl1.1-hmac libgcrypt20 libgcrypt20-hmac strongswan strongswan-hmac openssh-client openssh-server linux-image-fips \
    && pro detach --assume-yes


## Kairos setup
## From documentation: https://kairos.io/docs/reference/build-from-scratch/
RUN mkdir -p /run/lock
RUN mkdir -p /usr/libexec
RUN touch /usr/libexec/.keep

## Kairos required packages
## See: https://github.com/kairos-io/kairos/blob/master/images/Dockerfile.ubuntu-20-lts
RUN apt-get install -y --no-install-recommends \
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
    shim-signed \
    cloud-guest-utils \
    && apt-get remove -y unattended-upgrades && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy the Kairos framework files. We use master builds here for fedora. See https://quay.io/repository/kairos/framework?tab=tags for a list
COPY --from=kairos-fips / /

RUN sed -i 's/\bsource\b/./g' /system/oem/00_rootfs.yaml
RUN sed -i 's/\bsource\b/./g' /system/oem/09_openrc_services.yaml
RUN sed -i 's/\bsource\b/./g' /system/oem/50_recovery.yaml

# Copy the os-release file to identify the OS
COPY --from=osbuilder /workspace/os-release /etc/os-release

## Configuration
## Took from: https://github.com/kairos-io/kairos/blob/master/images/Dockerfile.ubuntu-20-lts
# workaround https://github.com/kairos-io/kairos/issues/949
COPY dracut-broken-iscsi-ubuntu-20.patch /
RUN cd /usr/lib/dracut/modules.d/95iscsi && patch < /dracut-broken-iscsi-ubuntu-20.patch && rm -rf /dracut-broken-iscsi-ubuntu-20.patch

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf
# CLEANUP
# Installing dracut and fips creates this default packages and symlinks and we dont want that
# We want to fully rebuild and link our initrd
RUN rm -Rf /boot/vmlinuz.old # symlink
RUN rm -Rf /boot/vmlinuz.img.old # symlink
RUN rm -Rf /boot/vmlinuz.img # symlink
RUN rm -Rf /boot/initrd.img.old # symlink to wrong initrd (no immucore, no kairos-agent)
RUN rm -Rf /boot/initrd.img # symlink to wrong initrd (no immucore, no kairos-agent)
RUN rm -Rf /boot/initrd.img-* # wrong initrd (no immucore, no kairos-agent)
## Generate initrd
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
RUN kernel=$(ls /lib/modules | head -n1) && \
            dracut -v -N -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd && depmod -a "${kernel}"
RUN rm -rf /boot/initramfs-*

# Fixup sudo perms
RUN chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo

# Symlink kernel HMAC
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac

RUN ln -s /usr/sbin/grub-install /usr/sbin/grub2-install
RUN ln -s /usr/bin/grub-editenv /usr/bin/grub2-editenv

# Clear cache
RUN rm -rf /var/cache/* && journalctl --vacuum-size=1K && rm /etc/machine-id && rm /var/lib/dbus/machine-id && rm /etc/hostname
