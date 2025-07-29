
# Kairos init image
FROM quay.io/kairos/kairos-init:v0.5.1 AS kairos-init

# Base ubuntu image (focal)
FROM ubuntu:focal as base

# Build the custom ubuntu image
FROM base

ARG KAIROS_VERSION=v3.4.2

# Don't get asked while running apt commands
ENV DEBIAN_FRONTEND=noninteractive

COPY --from=kairos-init /kairos-init /kairos-init
RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install --version "${KAIROS_VERSION}"

## THIS comes from the Ubuntu documentation: https://canonical-ubuntu-pro-client.readthedocs-hosted.com/en/latest/tutorials/create_a_fips_docker_image.html
## I've just added "linux-image-fips" in the package list
RUN --mount=type=secret,id=pro-attach-config \
    apt-get update \
    && apt-get install --no-install-recommends -y ubuntu-advantage-tools ca-certificates \
    && pro attach --attach-config /run/secrets/pro-attach-config \
    && apt-get upgrade -y \
    && apt-get install -y openssl libssl1.1 libssl1.1-hmac libgcrypt20 libgcrypt20-hmac strongswan strongswan-hmac openssh-client openssh-server linux-image-fips \
    && pro detach --assume-yes

COPY dracut-broken-iscsi-ubuntu-20.patch /
RUN cd /usr/lib/dracut/modules.d/95iscsi && patch < /dracut-broken-iscsi-ubuntu-20.patch && rm -rf /dracut-broken-iscsi-ubuntu-20.patch

COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init --version "${KAIROS_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends dracut dracut-network isc-dhcp-common isc-dhcp-client cloud-guest-utils \
    && apt-get remove -y unattended-upgrades && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Symlink kernel HMAC
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac