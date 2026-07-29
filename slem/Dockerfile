# syntax=docker/dockerfile:1.4
ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:v0.16.1
FROM ${KAIROS_INIT_IMAGE} AS kairos-init

# ---------------------------------------------------------------------------
# Stage 1: register against SCC to obtain the entitled, version-matched
# SLE 15 SP5 repositories. The SLE Micro image ships no SUSEConnect, so we use
# a BCI base (which can install it) purely to produce the RIS service +
# credentials that libzypp can then consume natively.
# ---------------------------------------------------------------------------
FROM registry.suse.com/bci/bci-base:15.5 AS scc
RUN zypper -n install -y suseconnect-ng
RUN --mount=type=secret,id=SUSE_REGCODE \
    SUSEConnect -r "$(cat /run/secrets/SUSE_REGCODE)" && \
    SUSEConnect -p sle-module-basesystem/15.5/x86_64 || true; \
    SUSEConnect -p PackageHub/15.5/x86_64 || true

# ---------------------------------------------------------------------------
# Stage 2: SLE Micro (for Rancher) 5.5 base built against the entitled repos.
# Using version-matched SP5 packages means kairos-init reinstalls a kernel +
# dracut that agree with the base image, so the initrd it rebuilds is bootable
# (the openSUSE Leap OSS mix downgraded dracut and produced an unbootable initrd).
# ---------------------------------------------------------------------------
FROM registry.suse.com/suse/sle-micro/5.5:latest

ARG KAIROS_VERSION=v4.1.2
ARG TRUSTED_BOOT=false

# Bring over the SCC registration so zypper here can pull the entitled repos.
COPY --from=scc /etc/zypp/credentials.d/ /etc/zypp/credentials.d/
COPY --from=scc /etc/zypp/services.d/ /etc/zypp/services.d/
COPY --from=scc /etc/zypp/repos.d/ /etc/zypp/repos.d/
COPY suse-build-key.asc /tmp/suse-build-key.asc

# refresh-services processes the copied RIS service (hits SCC with the
# credentials) and materialises the entitled repos; a plain refresh alone does
# not. Fail loudly if no enabled repos result.
# kairos-init's SLE Micro (Rancher) path also adds the openSUSE Leap OSS repo,
# whose signing key expired 2026-06-19, so a later `zypper refresh` across all
# repos aborts (exit 4). Disable repo-metadata gpg check globally so that stale
# repo does not break the build; package signatures are still verified (SUSE key
# imported above), and the real packages come from the valid SCC SP5 repos.
RUN rpm --import /tmp/suse-build-key.asc && rm -f /tmp/suse-build-key.asc && \
    sed -i '/^\[main\]/a repo_gpgcheck = off' /etc/zypp/zypp.conf && \
    rm -f /etc/zypp/repos.d/SLE_BCI.repo && \
    zypper --non-interactive --gpg-auto-import-keys refresh-services --force || true; \
    echo "=== enabled repositories ===" && zypper --non-interactive lr --uri && \
    zypper --non-interactive --gpg-auto-import-keys refresh

# SLE Micro for Rancher ships Rancher Elemental, a competing immutable-OS stack.
# Its dracut modules, systemd services and /system/oem layout files race with
# Kairos immucore and prevent sysroot.mount from landing. Remove before kairos-init.
RUN zypper --non-interactive rm -y --clean-deps \
        elemental elemental-register1.5 elemental-support1.5 \
        elemental-system-agent elemental-toolkit elemental-updater \
      2>/dev/null || true; \
    for svc in elemental-setup-reconcile elemental-register-reset \
               elemental-register elemental-setup-network \
               elemental-setup-fs elemental-populate-node-labels \
               elemental-system-agent elemental-setup-rootfs \
               elemental-setup-boot elemental-setup-initramfs \
               elemental-register-install elemental-immutable-rootfs; do \
      systemctl mask "${svc}.service" 2>/dev/null || true; \
    done; \
    rm -f /system/oem/*_elemental-* \
          /etc/dracut.conf.d/99-elemental-systemd.conf \
          /etc/dracut.conf.d/02-elemental-immutable-rootfs.conf \
          /etc/dracut.conf.d/02-elemental-setup-initramfs.conf \
          /etc/dracut.conf.d/50-elemental-initrd.conf; \
    rm -rf /usr/lib/dracut/modules.d/35network-legacy

COPY --from=kairos-init /kairos-init /kairos-init
RUN /kairos-init -l debug -m "generic" -t "${TRUSTED_BOOT}" --version "${KAIROS_VERSION}" && rm /kairos-init

# Scrub subscription data so credentials do not ship in the final image.
RUN rm -rf /etc/zypp/credentials.d/* /etc/zypp/services.d/* /etc/SUSEConnect 2>/dev/null || true
