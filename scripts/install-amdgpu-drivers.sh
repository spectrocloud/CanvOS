#!/usr/bin/env bash
#
# install-amdgpu-drivers.sh
#
# Pre-provision the AMD Instinct GPU kernel-mode driver INTO a CanvOS / Kairos
# Ubuntu base image, so a node booted from the image can run the AMD GPU Operator
# with `driver.enable=false` in a fully air-gapped environment.
#
# MODES (AMDGPU_DRIVER_SOURCE)
# ----------------------------
#   dkms  (default) -- install AMD's amdgpu-dkms. Two execution paths:
#                        (a) if AMDGPU_ARTIFACT_PATH is set (Earthly build via
#                            earthly.sh's prebuild helper), extract the pre-
#                            compiled modules + firmware + drop-ins from the
#                            tarball, depmod, rebuild initrd. Fast.
#                        (b) otherwise download from repo.radeon.com and
#                            DKMS-build against the image kernel in-place.
#                            Works under `docker run --privileged`; FAILS in
#                            Earthly's buildkit RUN sandbox at AMD's ./configure
#                            step -- use path (a) for Earthly.
#   inbox           -- do NOT install the AMD apt repo or amdgpu-dkms. Rely on
#                      the in-tree `amdgpu` module that Ubuntu ships with
#                      linux-modules-$(uname -r) and the firmware blobs in
#                      linux-firmware. Only ensures amdgpu autoloads. Choose
#                      this when you accept the in-tree driver's feature set
#                      (may miss recent SMU / per-SKU support).
#
# WHAT THIS COVERS (dkms mode, OS side only)
# ------------------------------------------
#   * build toolchain (gcc, make, dkms, kmod, libc headers)
#   * kernel headers matching the image kernel (via install-kernel-headers.sh)
#   * linux-modules-extra for the image kernel
#   * amdgpu-dkms + amdgpu-dkms-firmware, built against the IMAGE kernel
#   * amdgpu module autoload + initrd refresh
#   * a marker at /etc/canvos/amdgpu-driver-source recording which mode ran
#
# WHAT THIS DOES *NOT* COVER (both modes) -- ship these as container images in
# your content bundle, deployed by the AMD GPU Operator itself:
#   * ROCm user-space, device-plugin, node-labeller, metrics exporter, etc.
#
# At Helm-install time you MUST tell the operator the driver is pre-installed:
#     --set driver.enable=false        # note: "enable", not "enabled"
#
# WHY THE DKMS DANCE (same rationale as install-nvidia-drivers.sh)
# ---------------------------------------------------------------
# In an Earthly/Docker build `uname -r` is the BUILD HOST kernel, not the kernel
# baked into the image. We derive the target kernel from /lib/modules (the
# kernel that will actually boot) and force the DKMS build + module install +
# depmod against THAT kernel.
#
# TUNABLES (environment variables; all optional)
#   AMDGPU_DRIVER_SOURCE     dkms | inbox. Default: dkms.
#   AMDGPU_DRIVER_RELEASE    amdgpu-install release marker (URL segment under
#                            repo.radeon.com/amdgpu-install/<x>/). AMD publishes
#                            both ROCm-alias paths (7.2.1, 7.2.4) and driver-
#                            release-marker paths (30.30.1, 30.30.4, 31.30);
#                            either form is accepted. Default: 7.2.1 -- pairs
#                            with GPU Operator v1.5.0 per its release notes.
#                            The 31.x line is tech-preview and pairs only with
#                            ROCm 7.13.0 tech-preview; do not mix with a
#                            production operator. Ignored in inbox mode. See
#                            docs/amd-gpu-airgapped.md for the compat matrix.
#   AMDGPU_REBUILD_INITRD    "true" to rebuild the initrd for the image kernel.
#                            Default: false. amdgpu is intentionally NOT
#                            included in the initrd (see the dracut omit
#                            drop-in the script writes). The base image's
#                            existing initrd already handles rootfs mount;
#                            amdgpu loads after switch-root via
#                            /etc/modules-load.d/amdgpu.conf.
#
set -eo pipefail
set -u

log()  { echo "[install-amdgpu-drivers] $*"; }
warn() { echo "[install-amdgpu-drivers] WARNING: $*" >&2; }
die()  { echo "[install-amdgpu-drivers] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
AMDGPU_DRIVER_SOURCE="${AMDGPU_DRIVER_SOURCE:-dkms}"
AMDGPU_DRIVER_RELEASE="${AMDGPU_DRIVER_RELEASE:-7.2.1}"
AMDGPU_REBUILD_INITRD="${AMDGPU_REBUILD_INITRD:-false}"

case "${AMDGPU_DRIVER_SOURCE}" in
    dkms|inbox) ;;
    *) die "AMDGPU_DRIVER_SOURCE must be 'dkms' or 'inbox' (got: '${AMDGPU_DRIVER_SOURCE}')." ;;
esac

export DEBIAN_FRONTEND=noninteractive

command -v apt-get >/dev/null 2>&1 || die "this script only supports apt-based (Ubuntu/Debian) images."

# ---------------------------------------------------------------------------
# 1. Identify the kernel shipped in the image (NOT the build host kernel)
# ---------------------------------------------------------------------------
KVER="$(printf '%s\n' /lib/modules/* 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -V | tail -1)"
[ -n "${KVER}" ] || die "could not determine target kernel from /lib/modules."
log "Target (image) kernel: ${KVER}"
log "Driver source mode: ${AMDGPU_DRIVER_SOURCE}"
[ "${AMDGPU_DRIVER_SOURCE}" = "dkms" ] && log "AMD driver release: ${AMDGPU_DRIVER_RELEASE}"

# Ubuntu release codename (jammy / noble) read from the image itself.
codename=""
osid="ubuntu"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
    osid="${ID:-ubuntu}"
fi
[ -n "${codename}" ] || die "could not determine Ubuntu codename from /etc/os-release."

mkdir -p /etc/canvos

# ---------------------------------------------------------------------------
# INBOX MODE: skip the AMD apt repo and DKMS entirely. Rely on the in-tree
# amdgpu module shipped with the image's linux-modules-* package. Only ensure
# the module autoloads at boot, then rebuild initrd if requested.
# ---------------------------------------------------------------------------
if [ "${AMDGPU_DRIVER_SOURCE}" = "inbox" ]; then
    log "inbox mode: verifying in-tree amdgpu module is present under /lib/modules/${KVER}/kernel/..."
    if ! find "/lib/modules/${KVER}" -path '*/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko*' 2>/dev/null | grep -q .; then
        die "inbox mode selected but no in-tree amdgpu module found under /lib/modules/${KVER}/kernel/. \
This image kernel does not ship an in-tree amdgpu driver -- switch to \
AMDGPU_DRIVER_SOURCE=dkms or pick a different image kernel."
    fi

    log "Configuring amdgpu module autoload ..."
    cat > /etc/modules-load.d/amdgpu.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh (inbox mode)
# Load the in-tree AMD GPU driver at boot so the AMD GPU Operator sees a ready driver.
amdgpu
EOF

    log "Running depmod -a ${KVER} ..."
    depmod -a "${KVER}"

    # Even if AMDGPU_REBUILD_INITRD=true, we explicitly OMIT amdgpu from the
    # initrd. On multi-GPU MI systems (e.g. 8x MI325X, 8 XCP partitions each)
    # amdgpu init emits so many udev events that dracut's initqueue times out
    # waiting for udev-settle before rootfs pivot, leaving the node in
    # dracut-emergency. amdgpu isn't needed to mount root (NVMe/SATA use their
    # own drivers) so it's safe to load it *after* switch-root via
    # /etc/modules-load.d/amdgpu.conf where there is no timeout pressure.
    log "Configuring dracut to OMIT amdgpu from initrd (avoid init-time udev storm) ..."
    mkdir -p /etc/dracut.conf.d
    cat > /etc/dracut.conf.d/98-canvos-amdgpu-omit.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh
# Keep amdgpu (and its DKMS helpers) OUT of the initrd. amdgpu emits enough
# udev events at load time (per-XCP-partition, per-ring) to blow past dracut's
# initqueue timeout on multi-GPU systems, dropping the node into emergency
# mode. amdgpu is not required to mount the rootfs; systemd loads it via
# modules-load.d after switch-root.
omit_drivers+=" amdgpu amdttm amdkcl amd-sched amddrm_ttm_helper amddrm_buddy amddrm_exec amdxcp "
EOF

    if [ "${AMDGPU_REBUILD_INITRD}" = "true" ]; then
        if command -v dracut >/dev/null 2>&1; then
            log "Rebuilding initrd for ${KVER} (dracut, amdgpu omitted) ..."
            dracut -f "/boot/initrd-${KVER}" "${KVER}"
            ln -sf "initrd-${KVER}" /boot/initrd
        elif command -v update-initramfs >/dev/null 2>&1; then
            log "Rebuilding initramfs for ${KVER} (update-initramfs) ..."
            update-initramfs -u -k "${KVER}"
        else
            warn "no dracut or update-initramfs found; skipping initrd rebuild."
        fi
    fi

    printf 'AMDGPU_DRIVER_SOURCE=inbox\nKVER=%s\n' "${KVER}" > /etc/canvos/amdgpu-driver-source

    log "Done. Using in-tree amdgpu driver for kernel ${KVER}."
    log "Reminder: install the AMD GPU Operator with 'driver.enable=false'."
    exit 0
fi

# ---------------------------------------------------------------------------
# DKMS MODE with a pre-built artifact (produced by
# scripts/prebuild-amdgpu-artifact.sh on the build host).
#
# Buildkit's RUN sandbox breaks AMD's amdgpu-dkms ./configure heredoc probe,
# so we compile outside Earthly in `docker run --privileged` and consume the
# resulting tarball here. Structurally this branch just extracts the tarball,
# runs depmod against the target kernel, and rebuilds the initrd.
# ---------------------------------------------------------------------------
AMDGPU_ARTIFACT_PATH="${AMDGPU_ARTIFACT_PATH:-}"
if [ "${AMDGPU_DRIVER_SOURCE}" = "dkms" ] && [ -n "${AMDGPU_ARTIFACT_PATH}" ]; then
    log "dkms mode: consuming pre-built artifact ${AMDGPU_ARTIFACT_PATH}"
    [ -s "${AMDGPU_ARTIFACT_PATH}" ] || die "AMDGPU_ARTIFACT_PATH='${AMDGPU_ARTIFACT_PATH}' \
is not a non-empty file inside the build container. Verify the earthly.sh \
wrapper produced it and Earthly COPYed it in."

    log "Extracting artifact into root filesystem ..."
    tar -xzf "${AMDGPU_ARTIFACT_PATH}" -C / \
        || die "tar extraction of ${AMDGPU_ARTIFACT_PATH} failed."

    MODDIR="/lib/modules/${KVER}"
    if ! find "${MODDIR}/updates/dkms" -name 'amdgpu.ko*' 2>/dev/null | grep -q .; then
        find "${MODDIR}" -name 'amdgpu.ko*' 2>/dev/null | sed 's/^/    /' >&2 || true
        die "amdgpu module missing under ${MODDIR}/updates/dkms after extract. \
Artifact was built for a different kernel? Delete build/amdgpu-artifact-*.tar.gz \
and rebuild (AMDGPU_FORCE_REBUILD=1) or verify BASE_IMAGE matches."
    fi

    log "Running depmod -a ${KVER} ..."
    depmod -a "${KVER}" || die "depmod failed for ${KVER}."

    # Even if AMDGPU_REBUILD_INITRD=true, we explicitly OMIT amdgpu from the
    # initrd. On multi-GPU MI systems (e.g. 8x MI325X, 8 XCP partitions each)
    # amdgpu init emits so many udev events that dracut's initqueue times out
    # waiting for udev-settle before rootfs pivot, leaving the node in
    # dracut-emergency. amdgpu isn't needed to mount root (NVMe/SATA use their
    # own drivers) so it's safe to load it *after* switch-root via
    # /etc/modules-load.d/amdgpu.conf where there is no timeout pressure.
    log "Configuring dracut to OMIT amdgpu from initrd (avoid init-time udev storm) ..."
    mkdir -p /etc/dracut.conf.d
    cat > /etc/dracut.conf.d/98-canvos-amdgpu-omit.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh
# Keep amdgpu (and its DKMS helpers) OUT of the initrd. amdgpu emits enough
# udev events at load time (per-XCP-partition, per-ring) to blow past dracut's
# initqueue timeout on multi-GPU systems, dropping the node into emergency
# mode. amdgpu is not required to mount the rootfs; systemd loads it via
# modules-load.d after switch-root.
omit_drivers+=" amdgpu amdttm amdkcl amd-sched amddrm_ttm_helper amddrm_buddy amddrm_exec amdxcp "
EOF

    if [ "${AMDGPU_REBUILD_INITRD}" = "true" ]; then
        if command -v dracut >/dev/null 2>&1; then
            log "Rebuilding initrd for ${KVER} (dracut, amdgpu omitted) ..."
            dracut -f "/boot/initrd-${KVER}" "${KVER}"
            ln -sf "initrd-${KVER}" /boot/initrd
        elif command -v update-initramfs >/dev/null 2>&1; then
            log "Rebuilding initramfs for ${KVER} (update-initramfs) ..."
            update-initramfs -u -k "${KVER}"
        else
            warn "no dracut or update-initramfs found; skipping initrd rebuild."
        fi
    fi

    # Marker written by the prebuild is preserved from the tar. Overwrite
    # any prebuild-mode marker with the final in-image reality.
    printf 'AMDGPU_DRIVER_SOURCE=dkms (artifact)\nAMDGPU_DRIVER_RELEASE=%s\nKVER=%s\n' \
        "${AMDGPU_DRIVER_RELEASE}" "${KVER}" > /etc/canvos/amdgpu-driver-source

    log "Done. AMD amdgpu driver (release ${AMDGPU_DRIVER_RELEASE}, artifact) baked in for kernel ${KVER}."
    log "Reminder: install the AMD GPU Operator with 'driver.enable=false'."
    exit 0
fi

# ---------------------------------------------------------------------------
# DKMS MODE in-buildkit (fallback). Runs the full apt + DKMS build inside
# the image. This path fails inside Earthly's buildkit RUN sandbox at AMD's
# ./configure step (see docs) but is retained for:
#   - direct `docker run --privileged` invocations (proven working),
#   - the scripts/prebuild-amdgpu-artifact.sh helper, which uses this same
#     script inside the container it spawns.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 2. Build toolchain
# ---------------------------------------------------------------------------
log "Installing build toolchain ..."
apt-get update || true
# The full Kbuild bootstrap: gcc/make/libc from build-essential PLUS the
# tools that recent kernel Makefiles pull in unconditionally. Missing any of
# these fails AMD's amdgpu-dkms ./configure at "cannot detect CFLAGS..." --
# the failure mode is silent because CFLAGS-detection just runs `make -f -`
# and swallows stderr. We enumerate them explicitly instead of relying on
# --install-recommends (which would also pull other unwanted docs/data).
#   bc, bison, flex   : referenced by kernel Kbuild machinery
#   libelf-dev        : module utilities (modpost) + BPF
#   libssl-dev        : signing certificates / hash routines
#   dwarves           : pahole for BTF debuginfo (amdgpu-dkms explicitly Recommends this)
#   cpio, xz-utils    : initramfs assembly (may be needed by initramfs-tools trigger)
apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg \
    build-essential gcc make \
    dkms kmod libc6-dev initramfs-tools \
    bc bison flex libelf-dev libssl-dev dwarves \
    cpio xz-utils \
    || die "failed to install build toolchain."

# ---------------------------------------------------------------------------
# 3. Kernel headers + modules-extra matching the image kernel
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HEADERS_HELPER=""
for cand in "${SCRIPT_DIR}/install-kernel-headers.sh" /tmp/install-kernel-headers.sh; do
    [ -r "${cand}" ] && { HEADERS_HELPER="${cand}"; break; }
done

if [ -n "${HEADERS_HELPER}" ]; then
    log "Installing kernel headers via ${HEADERS_HELPER} ..."
    bash "${HEADERS_HELPER}" || warn "kernel-headers helper returned non-zero; continuing."
else
    log "Header helper not found; attempting a direct header install ..."
    apt-get install -y "linux-headers-${KVER}" || \
        apt-get install -y linux-headers-generic || \
        warn "could not install linux-headers-${KVER}."
fi

# amdgpu depends on modules that live in linux-modules-extra (e.g. for some
# PCIe / crypto / networking helpers). Best-effort -- may be absent if Ubuntu
# rotated the ABI out of the live mirror.
log "Installing linux-modules-extra-${KVER} (best-effort) ..."
apt-get install -y "linux-modules-extra-${KVER}" || \
    warn "linux-modules-extra-${KVER} not available; continuing."

# DKMS needs /lib/modules/<KVER>/build to point at the headers source tree.
if [ ! -e "/lib/modules/${KVER}/build" ]; then
    src="$(ls -d /usr/src/linux-headers-${KVER} 2>/dev/null | head -1)"
    if [ -n "${src}" ]; then
        ln -sfn "${src}" "/lib/modules/${KVER}/build"
        log "Linked /lib/modules/${KVER}/build -> ${src}"
    else
        warn "no /usr/src/linux-headers-${KVER}; DKMS build will likely fail."
    fi
fi

# ---------------------------------------------------------------------------
# 4. Register the AMD driver repo via the amdgpu-install package
#    The amdgpu-install .deb (AMD's blessed entry point) configures the correct
#    versioned driver apt repo + GPG key for the requested release. Its
#    filename carries a build number, so we auto-discover it from the directory
#    listing rather than hardcoding it.
# ---------------------------------------------------------------------------
inst_dir="https://repo.radeon.com/amdgpu-install/${AMDGPU_DRIVER_RELEASE}/${osid}/${codename}"
log "Locating amdgpu-install package under ${inst_dir}/ ..."
deb_name="$(curl -fsSL "${inst_dir}/" 2>/dev/null \
            | grep -oE 'amdgpu-install_[0-9A-Za-z._-]+_all\.deb' | sort -u | tail -1)"
[ -n "${deb_name}" ] || die "could not find an amdgpu-install package for driver \
release '${AMDGPU_DRIVER_RELEASE}' on ${codename} at ${inst_dir}/. Check available \
releases at https://repo.radeon.com/amdgpu-install/ and pick one that supports \
your image kernel (${KVER}); see docs/amd-gpu-airgapped.md for the mapping."

log "Installing ${deb_name} (configures the AMD driver apt repo) ..."
wget -qO /tmp/amdgpu-install.deb "${inst_dir}/${deb_name}" \
    || die "failed to download ${deb_name}."
apt-get install -y /tmp/amdgpu-install.deb || die "failed to install amdgpu-install."
rm -f /tmp/amdgpu-install.deb
apt-get update || warn "apt-get update after adding the AMD repo failed."

# ---------------------------------------------------------------------------
# 4b. Disable DKMS module signing before installing amdgpu-dkms.
#
# amdgpu-dkms (>= 6.18 range, and observed on 31.x releases) invokes mokutil
# from the DKMS sign_tool hook to enroll a Machine Owner Key, which reads
# /sys/firmware/efi/efivars. Docker/Earthly build containers don't expose
# efivars, so mokutil aborts with:
#     "EFI variables are not supported on this system /
#      /sys/firmware/efi/efivars not found, aborting."
# and the amdgpu-dkms postinst returns non-zero. Empty sign_tool tells DKMS
# to skip signing entirely, sidestepping the mokutil invocation.
#
# CAVEAT: modules produced this way are unsigned -- consistent with the
# Secure Boot / UKI limitation already documented in docs/amd-gpu-airgapped.md.
# ---------------------------------------------------------------------------
log "Disabling DKMS module signing (container has no UEFI efivars) ..."
mkdir -p /etc/dkms/framework.conf.d
cat > /etc/dkms/framework.conf.d/canvos-no-mok-signing.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh
# Empty sign_tool tells DKMS to skip module signing. Required for building
# amdgpu-dkms inside container image builds where /sys/firmware/efi/efivars
# is not available. Modules are unsigned; this path does not support Secure Boot.
sign_tool=""
EOF

# ---------------------------------------------------------------------------
# 5. Install the kernel-mode driver (amdgpu-dkms + firmware).
#    Any apt/postinst failure surfaces here -- DO NOT swallow errors; a broken
#    DKMS build must fail the image build so the user can fix AMDGPU_DRIVER_RELEASE
#    or fall back to AMDGPU_DRIVER_SOURCE=inbox.
# ---------------------------------------------------------------------------
log "Installing amdgpu-dkms + amdgpu-dkms-firmware ..."
if ! apt-get install -y --no-install-recommends amdgpu-dkms amdgpu-dkms-firmware; then
    # apt/postinst failure -- dump the DKMS build artifacts so root-causing
    # doesn't require an interactive session (Earthly's -i tty is often broken).
    log "apt install failed. Dumping DKMS build artifacts for diagnosis:"
    log "--- dkms status ---"
    dkms status 2>&1 | sed 's/^/    /' || true
    for f in /var/lib/dkms/amdgpu/*/build/make.log; do
        [ -r "$f" ] || continue
        log "--- ${f} (tail -150) ---"
        tail -n 150 "$f" | sed 's/^/    /' || true
    done
    log "--- environment probes ---"
    log "    kernel: $(uname -r); target KVER: ${KVER}"
    log "    linux-headers pkg: $(dpkg -l "linux-headers-${KVER}" 2>/dev/null | awk '/^ii/{print $2, $3}')"
    log "    /lib/modules/${KVER}/build: $(readlink -f "/lib/modules/${KVER}/build" 2>/dev/null || echo MISSING)"
    log "    /usr/src/linux-headers-${KVER}/Module.symvers: $(test -s "/usr/src/linux-headers-${KVER}/Module.symvers" && echo present || echo missing/empty)"
    log "    sign_tool drop-in: $(test -r /etc/dkms/framework.conf.d/canvos-no-mok-signing.conf && grep -E '^sign_tool' /etc/dkms/framework.conf.d/canvos-no-mok-signing.conf || echo MISSING)"
    log "    memory: $(awk '/MemAvailable/{print $2/1024" MiB avail"}' /proc/meminfo)"
    die "failed to install amdgpu-dkms (release '${AMDGPU_DRIVER_RELEASE}') for \
kernel ${KVER}. See make.log tail above. Common causes: (1) the AMD driver source \
in this release does not support this kernel -- bump AMDGPU_DRIVER_RELEASE (see \
docs/amd-gpu-airgapped.md); (2) linux-headers-${KVER} not installed / Module.symvers \
empty; (3) DKMS module signing failed reaching /sys/firmware/efi/efivars -- normally \
handled by the sign_tool='' drop-in above. Workaround: rerun with \
AMDGPU_DRIVER_SOURCE=inbox to use the in-tree amdgpu."
fi

# ---------------------------------------------------------------------------
# 6. Build the DKMS module against the IMAGE kernel (not the build host).
#    apt-get's postinst may have already tried against $KVER; we re-run
#    explicitly and let failures propagate (no `|| true`).
# ---------------------------------------------------------------------------
command -v dkms >/dev/null 2>&1 || die "dkms binary not found after installing amdgpu-dkms."

log "Building amdgpu DKMS module for kernel ${KVER} ..."
# `dkms status` differs across versions:
#   dkms 2.x: "amdgpu, 6.19.4, 6.14.0-36-generic, x86_64: installed"
#   dkms 3.x: "amdgpu/6.19.4, 6.14.0-36-generic, x86_64: installed"
# We want the module-name and source-version (not the kernel).
dkms_line="$(dkms status 2>/dev/null | grep -iE '^amdgpu[/,]' | head -1 || true)"
[ -n "${dkms_line}" ] || die "dkms status does not know about the amdgpu module \
after apt install -- driver package is broken or DKMS registration failed."

mod="$(printf '%s\n' "${dkms_line}" | sed -E 's/[,/:].*//' | tr -d ' ')"
ver="$(printf '%s\n' "${dkms_line}" | sed -E 's/^[^/,]+[/,] *//' | sed -E 's/[,:].*//' | tr -d ' ')"
# Fallback: grep any version-looking token if the second column wasn't the version.
if ! printf '%s' "${ver}" | grep -qE '^[0-9]+\.[0-9]+'; then
    ver="$(printf '%s\n' "${dkms_line}" | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1)"
fi
[ -n "${mod}" ] && [ -n "${ver}" ] || die "could not parse dkms status line: '${dkms_line}'"

log "  dkms build   ${mod}/${ver} -k ${KVER}"
if ! dkms build -m "${mod}" -v "${ver}" -k "${KVER}"; then
    log "DKMS build failed. Full make.log tail:"
    tail -n 60 "/var/lib/dkms/${mod}/${ver}/build/make.log" 2>&1 | sed 's/^/    /' || true
    die "DKMS build of ${mod}/${ver} against kernel ${KVER} failed. AMD driver \
release '${AMDGPU_DRIVER_RELEASE}' likely does not support this kernel. Either \
bump AMDGPU_DRIVER_RELEASE (see docs/amd-gpu-airgapped.md) or rerun with \
AMDGPU_DRIVER_SOURCE=inbox."
fi

log "  dkms install ${mod}/${ver} -k ${KVER}"
dkms install -m "${mod}" -v "${ver}" -k "${KVER}" --force \
    || die "dkms install of ${mod}/${ver} against kernel ${KVER} failed."

log "DKMS status:"; dkms status 2>&1 | sed 's/^/  /' || true

# ---------------------------------------------------------------------------
# 7. Verify the DKMS-built module actually landed under updates/dkms and that
#    dkms considers it installed for the target kernel. The in-tree amdgpu
#    that Ubuntu ships under kernel/... does NOT count -- we're only satisfied
#    if the OOT driver made it in.
# ---------------------------------------------------------------------------
MODDIR="/lib/modules/${KVER}"
dkms_mod_found=""
if find "${MODDIR}/updates" -name 'amdgpu.ko*' 2>/dev/null | grep -q .; then
    dkms_mod_found="yes"
fi

dkms_installed=""
if dkms status 2>/dev/null \
    | grep -iE "^amdgpu[/,][^,]*,[[:space:]]*${KVER}[,]" \
    | grep -q ': installed'; then
    dkms_installed="yes"
fi

if [ -z "${dkms_mod_found}" ] || [ -z "${dkms_installed}" ]; then
    log "Verification failed:"
    log "  updates/dkms module present under ${MODDIR}/updates: ${dkms_mod_found:-no}"
    log "  dkms status shows 'installed' for kernel ${KVER}:    ${dkms_installed:-no}"
    find "${MODDIR}" -name 'amdgpu.ko*' 2>/dev/null | sed 's/^/    /' || true
    die "amdgpu DKMS module was NOT built+installed for kernel ${KVER}. The \
in-tree amdgpu (if any) is NOT sufficient in dkms mode -- rerun with \
AMDGPU_DRIVER_SOURCE=inbox if that is what you want."
fi

log "Verified: amdgpu DKMS module installed for ${KVER}."
find "${MODDIR}/updates" -name 'amdgpu.ko*' 2>/dev/null | sed 's/^/  /'

# ---------------------------------------------------------------------------
# 8. Autoload amdgpu at boot (no blacklist needed -- dkms replaces the in-tree
#    module of the same name via depmod's updates/ override).
# ---------------------------------------------------------------------------
log "Configuring amdgpu module autoload ..."
cat > /etc/modules-load.d/amdgpu.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh (dkms mode)
# Load the AMD GPU driver at boot so the AMD GPU Operator sees a ready driver.
amdgpu
EOF

# ---------------------------------------------------------------------------
# 9. depmod for the target kernel so modprobe resolves amdgpu at boot
# ---------------------------------------------------------------------------
log "Running depmod -a ${KVER} ..."
depmod -a "${KVER}" || warn "depmod reported an error."

# ---------------------------------------------------------------------------
# 10. Drop dracut config that OMITS amdgpu from any rebuilt initrd. See the
# equivalent block in the artifact / inbox branches for full rationale --
# multi-GPU amdgpu init blows past initqueue's timeout when loaded early.
# ---------------------------------------------------------------------------
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/98-canvos-amdgpu-omit.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh
# Keep amdgpu (and its DKMS helpers) OUT of the initrd. See install script.
omit_drivers+=" amdgpu amdttm amdkcl amd-sched amddrm_ttm_helper amddrm_buddy amddrm_exec amdxcp "
EOF

# ---------------------------------------------------------------------------
# 11. Rebuild the initrd for the target kernel (amdgpu omitted per above).
# ---------------------------------------------------------------------------
if [ "${AMDGPU_REBUILD_INITRD}" = "true" ] && command -v dracut >/dev/null 2>&1; then
    log "Rebuilding initrd for ${KVER} (dracut, amdgpu omitted) ..."
    if dracut -f "/boot/initrd-${KVER}" "${KVER}"; then
        ln -sf "initrd-${KVER}" /boot/initrd
    else
        warn "dracut initrd rebuild failed."
    fi
elif [ "${AMDGPU_REBUILD_INITRD}" = "true" ] && command -v update-initramfs >/dev/null 2>&1; then
    log "Rebuilding initramfs for ${KVER} (update-initramfs) ..."
    update-initramfs -u -k "${KVER}" || warn "update-initramfs failed."
fi

# ---------------------------------------------------------------------------
# 11. Record what we did so ops can query it on-node.
# ---------------------------------------------------------------------------
printf 'AMDGPU_DRIVER_SOURCE=dkms\nAMDGPU_DRIVER_RELEASE=%s\nAMDGPU_DKMS_MODULE=%s/%s\nKVER=%s\n' \
    "${AMDGPU_DRIVER_RELEASE}" "${mod}" "${ver}" "${KVER}" \
    > /etc/canvos/amdgpu-driver-source

# ---------------------------------------------------------------------------
# 12. Cleanup apt caches to keep the image lean
# ---------------------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Done. AMD amdgpu driver (release ${AMDGPU_DRIVER_RELEASE}) baked in for kernel ${KVER}."
log "Reminder: install the AMD GPU Operator with 'driver.enable=false'."
