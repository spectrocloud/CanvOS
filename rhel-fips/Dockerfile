# Kairos init image
FROM quay.io/kairos/kairos-init:v0.5.14 AS kairos-init

FROM registry.access.redhat.com/ubi8/ubi-init:8.7-10 as base

ARG USERNAME
ARG PASSWORD

# Generate os-release file
ARG KAIROS_VERSION=v3.5.0

# Don't get asked while running apt commands
ENV DEBIAN_FRONTEND=noninteractive

RUN dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
# Subscription manager in redhat does not run directly in containers unless you run on a redhat host, hence we remove the rhsm-host, login to the redhat subscription and add the repos
RUN rm /etc/rhsm-host && subscription-manager register --username ${USERNAME} --password ${PASSWORD} \
  && yum repolist \
  && subscription-manager attach --auto \
  && subscription-manager repos --enable rhel-8-for-x86_64-appstream-rpms \
  && yum repolist
RUN echo "install_weak_deps=False" >> /etc/dnf/dnf.conf

COPY overlay/rhel8/ /

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

COPY --from=kairos-init /kairos-init /kairos-init
RUN /kairos-init -l debug -s install --fips --version "${KAIROS_VERSION}"

COPY overlay/rhel8/ /

RUN mkdir -p /run/lock && \
  touch /usr/libexec/.keep

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init --version "${KAIROS_VERSION}"

RUN dnf install -y dracut dracut-network dracut-live dracut-squash dhcp-client \
    && dnf clean all

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac

# Disable SELinux
RUN echo "SELINUX=disabled" > /etc/selinux/config

RUN rm -rf /boot/initramfs-*

COPY overlay/rhel8/ /