# syntax=docker/dockerfile:1.4
# kairos-init is tagged with the Kairos version it installs.
ARG KAIROS_VERSION=v4.4.0
ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:${KAIROS_VERSION}
FROM ${KAIROS_INIT_IMAGE} AS kairos-init

# ---------------------------------------------------------------------------
# Stage 1: register against SCC to obtain the entitled, version-matched
# SLE 15 SP5 repositories. The SLE Micro image ships no SUSEConnect, so we use
# a BCI base (which can install it) purely to produce the RIS service +
# credentials that libzypp can then consume natively.
#
# SCC_NONCE (a timestamp from docker-bake.hcl) makes every build register a
# fresh system: the `deregister` stage below removes it again, so a cached
# registration would hold dead credentials.
# ---------------------------------------------------------------------------
FROM registry.suse.com/bci/bci-base:15.5 AS scc
ARG SCC_NONCE
RUN zypper -n install -y suseconnect-ng
RUN --mount=type=secret,id=SUSE_REGCODE,required=true \
    set -e; \
    echo "SCC registration ${SCC_NONCE}"; \
    arch="$(uname -m)"; \
    SUSEConnect -r "$(cat /run/secrets/SUSE_REGCODE)"; \
    SUSEConnect -p "sle-module-basesystem/15.5/${arch}"; \
    SUSEConnect -p "PackageHub/15.5/${arch}"

# ---------------------------------------------------------------------------
# Stage 2: SLE Micro (for Rancher) 5.5 base built against the entitled repos.
# Using version-matched SP5 packages means kairos-init reinstalls a kernel +
# dracut that agree with the base image, so the initrd it rebuilds is bootable
# (the openSUSE Leap OSS mix downgraded dracut and produced an unbootable initrd).
# ---------------------------------------------------------------------------
FROM registry.suse.com/suse/sle-micro/5.5:latest AS build

ARG KAIROS_VERSION
ARG MODEL=generic
ARG TRUSTED_BOOT=false

COPY suse-build-key.asc /tmp/suse-build-key.asc

# kairos-init's SLE Micro (Rancher) path also adds the openSUSE Leap OSS repo,
# whose signing key expired 2026-06-19, so a later `zypper refresh` across all
# repos aborts (exit 4). Disable repo-metadata gpg check globally so that stale
# repo does not break the build; package signatures are still verified (SUSE key
# imported here), and the real packages come from the valid SCC SP5 repos.
RUN rpm --import /tmp/suse-build-key.asc && rm -f /tmp/suse-build-key.asc && \
    sed -i '/^\[main\]/a repo_gpgcheck = off' /etc/zypp/zypp.conf

# The SCC registration (credentials, RIS service, repos) is bind-mounted from the
# scc stage, never COPYed: rw bind-mount changes are discarded after the RUN, so
# no credentials or tokenised repo URLs reach an image layer. Everything that
# needs the entitled repos therefore runs in this one RUN.
#
# refresh-services processes the RIS service (hits SCC with the credentials) and
# materialises the entitled repos; a plain refresh alone does not.
# `zypper lr -E` fails when no repo is enabled, so a failed registration stops
# here instead of later with missing packages. lr is printed without --uri: SCC
# repo URLs carry access tokens and must not land in the build log.
#
# SLE Micro for Rancher ships Rancher Elemental, a competing immutable-OS stack.
# Its dracut modules, systemd services and /system/oem layout files race with
# Kairos immucore and prevent sysroot.mount from landing. Remove before kairos-init.
#
# PE-9246: /system/oem/08_boot_assessment.yaml is an Elemental artifact too --
# it defines the same GRUB boot-assessment hook that kairos-init later
# re-implements in /system/oem/08_grub.yaml, and both files' after-install
# steps append the same source block to /run/initramfs/cos-state/grubcustom,
# so on the first post-upgrade boot GRUB runs the assessment twice in one
# session and immediately picks fallback with upgrade_failure. The file has
# no "elemental" in its name, so the *_elemental-* glob below misses it;
# list it explicitly.
RUN --mount=type=bind,from=scc,source=/etc/zypp/credentials.d,target=/etc/zypp/credentials.d,rw \
    --mount=type=bind,from=scc,source=/etc/zypp/services.d,target=/etc/zypp/services.d,rw \
    --mount=type=bind,from=scc,source=/etc/zypp/repos.d,target=/etc/zypp/repos.d,rw \
    --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    set -e; \
    rm -f /etc/zypp/repos.d/SLE_BCI.repo; \
    zypper --non-interactive --gpg-auto-import-keys refresh-services --force; \
    echo "=== enabled repositories ==="; \
    zypper --non-interactive lr -E; \
    zypper --non-interactive --gpg-auto-import-keys refresh; \
    zypper --non-interactive rm -y --clean-deps \
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
          /system/oem/08_boot_assessment.yaml \
          /etc/dracut.conf.d/99-elemental-systemd.conf \
          /etc/dracut.conf.d/02-elemental-immutable-rootfs.conf \
          /etc/dracut.conf.d/02-elemental-setup-initramfs.conf \
          /etc/dracut.conf.d/50-elemental-initrd.conf; \
    /kairos-init -l debug -m "${MODEL}" -t "${TRUSTED_BOOT}" --version "${KAIROS_VERSION}"; \
    zypper --non-interactive clean --all

# Workaround for a kairos-agent v2.30.2 install-time mount-lifecycle bug:
# 08_grub.yaml's after-install "Grub branding" cp writes /grubmenu to
# /tmp/mnt/STATE, which is a tmpfs directory on SUSE because COS_STATE is
# already mounted at /run/cos/state and kairos's own Mount step therefore
# fails. The file is lost on reboot and GRUB cannot find the Palette
# Registration menuentry. This overlay re-does the copy in
# after-install-chroot against /oem (COS_OEM, which GRUB also searches).
COPY oem/09_grub_branding_fixup.yaml /system/oem/09_grub_branding_fixup.yaml

# Mozilla bug 2083449: distrust the roots that chain to the compromised eMudhra intermediates.
# Bind-mounted from the `scripts` build context; no layer.
RUN --mount=type=bind,from=scripts,source=distrust-emudhra-roots.sh,target=/tmp/distrust-emudhra-roots.sh \
    sh /tmp/distrust-emudhra-roots.sh

# ---------------------------------------------------------------------------
# Deregister the SCC system created by the scc stage, so builds do not pile up
# registered systems. COPY --from=build orders it after every step that uses the
# registration; the final stage mounts its marker so bake always runs it.
# ---------------------------------------------------------------------------
FROM scc AS deregister
COPY --from=build /etc/os-release /tmp/built-os-release
RUN SUSEConnect -d && touch /deregistered

FROM build
RUN --mount=type=bind,from=deregister,source=/deregistered,target=/tmp/deregistered \
    test -f /tmp/deregistered
