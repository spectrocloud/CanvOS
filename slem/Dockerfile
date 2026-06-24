# syntax=docker/dockerfile:1.4
ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:v0.14.0
FROM ${KAIROS_INIT_IMAGE} AS kairos-init

# There is no "SLE Micro for Rancher" 5.5 image (the Rancher flavor stopped at
# 5.4); 5.5 ships only as the standard SLE Micro image.
FROM registry.suse.com/suse/sle-micro/5.5:latest

ARG KAIROS_VERSION=v4.0.3
ARG TRUSTED_BOOT=false

# Register against SCC to enable the version-matched SLE Micro 5.5 (SLE 15 SP5)
# update repos plus PackageHub. Using the real product repos (instead of mixing
# in older openSUSE Leap packages) means kairos-init installs a kernel / dracut /
# mkinitrd set that actually resolves. The regcode is passed as a BuildKit secret
# so it never persists in an image layer.
RUN --mount=type=secret,id=SUSE_REGCODE \
    SUSEConnect -r "$(cat /run/secrets/SUSE_REGCODE)" && \
    SUSEConnect -p PackageHub/15.5/x86_64 && \
    zypper --non-interactive --gpg-auto-import-keys refresh

COPY --from=kairos-init /kairos-init /kairos-init
RUN /kairos-init -l debug -m "generic" -t "${TRUSTED_BOOT}" --version "${KAIROS_VERSION}" && rm /kairos-init

# Deregister and scrub subscription data so credentials/repos do not ship in the
# final image.
RUN SUSEConnect -d || true; \
    rm -rf /etc/zypp/credentials.d/* /etc/zypp/services.d/* \
           /etc/zypp/repos.d/*.repo /etc/SUSEConnect 2>/dev/null || true
