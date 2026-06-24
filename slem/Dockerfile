ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:v0.14.0
FROM ${KAIROS_INIT_IMAGE} AS kairos-init

# registry.suse.com/suse/sle-micro/5.5 is actually "SLE Micro for Rancher 5.5"
# (os-release ID=sle-micro-rancher). kairos-init recognises it and builds it by
# mixing in the openSUSE Leap 15.5 OSS repo; no SUSE subscription is required.
FROM registry.suse.com/suse/sle-micro/5.5:latest

ARG KAIROS_VERSION=v4.0.3
ARG TRUSTED_BOOT=false

# Two 5.5-specific problems must be handled before kairos-init runs:
#   1. The Leap OSS packages are signed by the "SuSE Package Signing Key"
#      (70AF9E8139DB7C82), which is not in this image's rpm keyring, so installs
#      fail with NOKEY. Import it.
#   2. The base ships a newer dracut (...400) than Leap 15.5 OSS (...360). The
#      OSS kernel needs the 'mkinitrd' capability that only dracut-mkinitrd-
#      deprecated (paired with dracut-360) provides, so zypper would have to
#      *downgrade* dracut and aborts in non-interactive mode. Pre-align dracut
#      and install the mkinitrd provider here so kairos-init's later
#      "Install kernel packages" stage resolves cleanly.
COPY suse-build-key.asc /tmp/suse-build-key.asc
RUN rpm --import /tmp/suse-build-key.asc && rm -f /tmp/suse-build-key.asc && \
    printf '%s\n' \
        '[opensuse-oss]' \
        'name=opensuse-oss' \
        'enabled=1' \
        'autorefresh=0' \
        'baseurl=https://download.opensuse.org/distribution/leap/15.5/repo/oss/' \
        > /etc/zypp/repos.d/oss.repo && \
    zypper --non-interactive --gpg-auto-import-keys refresh && \
    zypper --non-interactive install --allow-downgrade --allow-vendor-change --force-resolution \
        dracut dracut-mkinitrd-deprecated

COPY --from=kairos-init /kairos-init /kairos-init
RUN /kairos-init -l debug -m "generic" -t "${TRUSTED_BOOT}" --version "${KAIROS_VERSION}" && rm /kairos-init
