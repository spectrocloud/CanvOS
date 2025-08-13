# Kairos init image
FROM quay.io/kairos/kairos-init:v0.5.10 AS kairos-init

FROM registry.access.redhat.com/ubi8/ubi-init:8.7-10 as base

ARG USERNAME
ARG PASSWORD
ARG VERSION=v0.0.1

# Install util-linux for disk partitioning and persistent storage setup
RUN dnf install -y util-linux

# Try to set up Red Hat subscription if credentials are provided, otherwise use UBI repos
RUN if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then \
        rm -f /etc/rhsm-host && \
        subscription-manager register --username ${USERNAME} --password ${PASSWORD} && \
        subscription-manager attach --auto && \
        subscription-manager repos --enable rhel-8-for-x86_64-baseos-rpms --enable rhel-8-for-x86_64-appstream-rpms; \
    else \
        echo "No subscription credentials provided, using UBI repositories"; \
    fi

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install --fips --version "${VERSION}"

# Install dracut packages after kairos-init to prevent them from being removed
RUN dnf install -y dracut dracut-live dracut-network dracut-squash

# Copy the custom dracut config file which enables fips
COPY dracut.conf /etc/dracut.conf.d/kairos-fips.conf

# Debug: Check what's available before init
RUN ls -la /boot/ || true && \
    ls -la /lib/modules/ || true && \
    dracut --version || true

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init --skip-step cleanup,initrd --version "${VERSION}"

# Symlink kernel HMAC
RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && ln -sf ."${kernel#/boot/}".hmac /boot/.vmlinuz.hmac
