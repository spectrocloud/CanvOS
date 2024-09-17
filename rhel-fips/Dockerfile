ARG BASE_IMAGE=registry.access.redhat.com/ubi8/ubi-init:8.7-10

FROM $BASE_IMAGE as base

ARG USERNAME
ARG PASSWORD

# Generate os-release file
FROM quay.io/kairos/osbuilder-tools:v0.7.11 as osbuilder
RUN zypper install -y gettext && zypper clean
RUN mkdir /workspace
COPY --from=base /etc/os-release /workspace/os-release
# You should change the following values according to your own versioning and other details
RUN OS_NAME=kairos-core-rhel-fips \
  OS_VERSION=v3.0.14 \
  OS_ID="kairos" \
  BUG_REPORT_URL="https://github.com/spectrocloud/pxke-samples/issues" \
  HOME_URL="https://github.com/spectrocloud/pxke-samples" \
  OS_REPO="quay.io/spectrocloud/fedora-fips" \
  OS_LABEL="latest" \
  GITHUB_REPO="spectrocloud/pxke-samples" \
  VARIANT="fips" \
  FLAVOR="rhel" \
  /update-os-release.sh

FROM base

RUN dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
# Subscription manager in redhat does not run directly in containers unless you run on a redhat host, hence we remove the rhsm-host, login to the redhat subscription and add the repos
RUN rm /etc/rhsm-host && subscription-manager register --username ${USERNAME} --password ${PASSWORD} \
  && yum repolist \
  && subscription-manager attach --auto \
  && subscription-manager repos --enable rhel-8-for-x86_64-appstream-rpms \
  && yum repolist
RUN echo "install_weak_deps=False" >> /etc/dnf/dnf.conf
# Generate machine-id because https://bugzilla.redhat.com/show_bug.cgi?id=1737355#c6
RUN uuidgen > /etc/machine-id && dnf install -y \
    squashfs-tools \ 
    dracut-live \
    livecd-tools \
    dracut-squash \
    dracut-network \
    efibootmgr \
    dhclient \
    audit \
    sudo \
    systemd \
    systemd-networkd \
    systemd-timesyncd \
    parted \
    dracut \
    e2fsprogs \
    dosfstools \
    coreutils-single \
    device-mapper \
    grub2 \
    which \
    curl \
    nano \
    gawk \
    haveged \
    polkit \
    ncurses \
    tar \
    kbd \
    lvm2 \
    zstd \
    openssh-server \
    openssh-clients \
    shim-x64 \
    grub2-pc \
    grub2-efi-x64 \
    grub2-efi-x64-modules \
    open-vm-tools \
    iscsi-initiator-utils \
    iptables ethtool socat iproute-tc conntrack \
    kernel kernel-modules kernel-modules-extra \
    rsync jq && dnf clean all

RUN mkdir -p /run/lock && \
  touch /usr/libexec/.keep

# Copy the os-release file to identify the OS
COPY --from=osbuilder /workspace/os-release /etc/os-release

COPY --from=gcr.io/spectro-images-public/kairos/framework:v2.11.7-fips / /

RUN sed -i 's/\bsource\b/./g' /system/oem/00_rootfs.yaml
RUN sed -i 's/\bsource\b/./g' /system/oem/09_openrc_services.yaml
RUN sed -i 's/\bsource\b/./g' /system/oem/50_recovery.yaml

COPY overlay/rhel8 /

# Configure the box. The ubi image masks services for containers, we unmask them 
RUN systemctl list-unit-files |grep masked |cut -f 1 -d " " | xargs systemctl unmask
RUN systemctl enable getty@tty1.service
RUN systemctl enable getty@tty2.service
RUN systemctl enable getty@tty3.service
RUN systemctl enable systemd-networkd
RUN systemctl enable systemd-resolved
RUN systemctl enable sshd
RUN systemctl disable selinux-autorelabel-mark.service 
#RUN systemctl enable tmp.mount

# Copy the custom dracut config file
COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

## Generate initrd
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
RUN kernel=$(ls /lib/modules | head -n1) && \
            dracut -v -N -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd && depmod -a "${kernel}"

# Symlink kernel HMAC
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac

# Disable SELinux
RUN echo "SELINUX=disabled" > /etc/selinux/config

RUN rm -rf /boot/initramfs-*
