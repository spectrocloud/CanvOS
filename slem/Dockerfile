FROM quay.io/kairos/kairos-init:v0.5.26 AS kairos-init

FROM registry.suse.com/suse/sle-micro-rancher/5.4:latest

ADD repos/SUSE* /etc/zypp/repos.d/
ADD services/* /etc/zypp/services.d/
RUN zypper --gpg-auto-import-keys ref

ADD repos/opensuse* /etc/zypp/repos.d/
RUN zypper --gpg-auto-import-keys ref

ARG KAIROS_VERSION=v3.5.7
COPY --from=kairos-init /kairos-init /kairos-init

RUN zypper -n in \
  --no-recommends \
  --force-resolution \
  --allow-downgrade \
  file gawk iptables less nano sudo tar zstd rsync lvm2 jq dosfstools e2fsprogs parted logrotate \
  curl bash-completion conntrack-tools cryptsetup coreutils device-mapper fail2ban findutils \
  growpart gptfdisk haveged htop iproute2 iputils issue-generator lsscsi mdadm multipath-tools \
  nfs-client open-iscsi openssh open-vm-tools pigz policycoreutils polkit procps \
  qemu-guest-agent strace systemd systemd-network timezone tmux vim which tpm* nethogs patch shim iw \
  grub2-i386-pc grub2-x86_64-efi kernel-firmware-all dracut squashfs dhcp-client rsyslog logrotate

RUN systemctl disable NetworkManager.service NetworkManager-wait-online.service

RUN /kairos-init -l debug -m "generic" -t false --version "${KAIROS_VERSION}" --skip-step installPackages && rm /kairos-init
