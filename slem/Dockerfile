ARG BASE_IMAGE=registry.suse.com/suse/sle-micro-rancher/5.4:latest
FROM $BASE_IMAGE

RUN zypper ar -G https://download.opensuse.org/repositories/utilities/openSUSE_Factory/utilities.repo || true && \
    zypper ref

ADD repos/SUSE* /etc/zypp/repos.d/
ADD services/* /etc/zypp/services.d/
RUN zypper --gpg-auto-import-keys ref
RUN zypper in --force-resolution -y \
    cryptsetup \
    nfs-client \
    kernel-firmware-all \
    systemd-network \
    polkit \
    rng-tools \
    nano \
    && zypper cc
ADD repos/opensuse* /etc/zypp/repos.d/
RUN zypper --gpg-auto-import-keys ref
RUN zypper in --force-resolution -y --no-allow-vendor-change \
    htop \
    fail2ban \
    lldpd \
    nethogs \
    && zypper cc
# NOTE: removed dhcp-client
RUN mkdir -p /run/lock
RUN mkdir -p /usr/libexec
RUN touch /usr/libexec/.keep
COPY --from=quay.io/kairos/framework:v2.4.3_generic / /

RUN mkdir -p /etc/dnf
RUN echo "install_weak_deps=False" > /etc/dnf/dnf.conf

RUN zypper in --force-resolution -y \
    bash-completion \
    conntrack-tools \
    coreutils \
    curl \
    device-mapper \
    dhcp-client \
    dosfstools \
    dracut \
    e2fsprogs \
    fail2ban \
    findutils \
    gawk \
    growpart \
    gptfdisk \
    haveged \
    htop \
    iproute2 \
    iptables \
    iputils \
    issue-generator \
    jq \
    less \
    logrotate \
    lsscsi \
    lvm2 \
    mdadm \
    multipath-tools \
    nano \
    nohang \
    open-iscsi \
    openssh \
    open-vm-tools \
    parted \
    pigz \
    policycoreutils \
    polkit \
    procps \
    rng-tools \
    rsync \
    squashfs \
    strace \
    sudo \
    systemd \
    systemd-network \
    tar \
    timezone \
    tmux \
    vim \
    which \
    tpm2* \
    && zypper cc

## Generate initrd
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
RUN kernel=$(ls /lib/modules | head -n1) && \
            dracut -v -N -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd && depmod -a "${kernel}"
RUN kernel=$(ls /lib/modules | head -n1) && dracut -f "/boot/initrd-${kernel}" "${kernel}" && ln -sf "initrd-${kernel}" /boot/initrd
RUN rm -rf /boot/initramfs-*
RUN rm -rf /etc/zypp/repos.d/*
RUN rm -rf /etc/zypp/services.d/*