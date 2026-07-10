#!/usr/bin/env bash
#
# install-amdgpu-drivers.sh
#
# Pre-install the AMD Instinct GPU kernel-mode driver (amdgpu-dkms) INTO a
# CanvOS / Kairos Ubuntu base image, so a node booted from the image can run
# the AMD GPU Operator in a fully air-gapped environment WITHOUT any host-side
# network access and WITHOUT the operator building/managing the driver.
#
# WHAT THIS COVERS (OS side only)
# -------------------------------
#   * build toolchain (gcc, make, dkms, kmod, libc headers)
#   * kernel headers that match the kernel shipped in the image
#     (delegated to scripts/install-kernel-headers.sh)
#   * linux-modules-extra for the image kernel (amdgpu pulls modules from it)
#   * the AMD amdgpu kernel module built with DKMS against the IMAGE kernel
#     (amdgpu-dkms + amdgpu-dkms-firmware)
#   * amdgpu module autoload + initrd refresh
#
# WHAT THIS DOES *NOT* COVER (ships as container images in your content bundle,
# deployed by the AMD GPU Operator itself):
#   * ROCm user-space, device-plugin, node-labeller, metrics exporter, etc.
#
# At Helm-install time you MUST tell the operator the driver is pre-installed:
#     --set driver.enable=false        # note: "enable", not "enabled"
#   (the operator then "directly uses inbox or pre-installed AMD GPU drivers"
#    and only deploys device-plugin / node-labeller / metrics-exporter)
#
# WHY THE DKMS DANCE (same rationale as install-nvidia-drivers.sh)
# ---------------------------------------------------------------
# In an Earthly/Docker build `uname -r` is the BUILD HOST kernel, not the kernel
# baked into the image. We derive the target kernel from /lib/modules (the
# kernel that will actually boot) and force the DKMS build + module install +
# depmod against THAT kernel.
#
# NOTE ON BLACKLISTING
# --------------------
# Unlike NVIDIA (where the open-source `nouveau` driver must be blacklisted),
# amdgpu-dkms REPLACES the in-tree `amdgpu` module (same module name). depmod
# prefers the updates/dkms copy, so there is nothing to blacklist -- we simply
# ensure amdgpu autoloads.
#
# CONNECTIVITY
# ------------
# This script runs at BUILD time, where the builder has internet. It bakes
# everything into the image. The resulting image needs no network at boot.
#
# TUNABLES (environment variables; all optional)
#   AMDGPU_ROCM_VERSION      ROCm/driver release to install (e.g. 7.2.4, 6.4.4,
#                            6.2.2). Default: 7.2.4
#                            Must match the ROCm version of the operator images
#                            you bundle. This selects the amdgpu-install package
#                            under repo.radeon.com/amdgpu-install/<version>/,
#                            which configures the matching driver apt repo.
#   AMDGPU_REBUILD_INITRD    "true" to rebuild the initrd for the image kernel.
#                            Default: true
#
set -u

log()  { echo "[install-amdgpu-drivers] $*"; }
warn() { echo "[install-amdgpu-drivers] WARNING: $*" >&2; }
die()  { echo "[install-amdgpu-drivers] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
AMDGPU_ROCM_VERSION="${AMDGPU_ROCM_VERSION:-7.2.4}"
AMDGPU_REBUILD_INITRD="${AMDGPU_REBUILD_INITRD:-true}"

export DEBIAN_FRONTEND=noninteractive

command -v apt-get >/dev/null 2>&1 || die "this script only supports apt-based (Ubuntu/Debian) images."

# ---------------------------------------------------------------------------
# 1. Identify the kernel shipped in the image (NOT the build host kernel)
# ---------------------------------------------------------------------------
KVER="$(printf '%s\n' /lib/modules/* 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -V | tail -1)"
[ -n "${KVER}" ] || die "could not determine target kernel from /lib/modules."
log "Target (image) kernel: ${KVER}"
log "AMD ROCm/driver version: ${AMDGPU_ROCM_VERSION}"

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

# ---------------------------------------------------------------------------
# 2. Build toolchain
# ---------------------------------------------------------------------------
log "Installing build toolchain ..."
apt-get update || true
apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg \
    build-essential gcc make \
    dkms kmod libc6-dev initramfs-tools \
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
#    versioned driver apt repo + GPG key for the requested ROCm release. Its
#    filename carries a build number, so we auto-discover it from the directory
#    listing rather than hardcoding it.
# ---------------------------------------------------------------------------
inst_dir="https://repo.radeon.com/amdgpu-install/${AMDGPU_ROCM_VERSION}/${osid}/${codename}"
log "Locating amdgpu-install package under ${inst_dir}/ ..."
deb_name="$(curl -fsSL "${inst_dir}/" 2>/dev/null \
            | grep -oE 'amdgpu-install_[0-9A-Za-z._-]+_all\.deb' | sort -u | tail -1)"
[ -n "${deb_name}" ] || die "could not find an amdgpu-install package for ROCm \
${AMDGPU_ROCM_VERSION} / ${codename} at ${inst_dir}/. \
Check available versions at https://repo.radeon.com/amdgpu-install/"

log "Installing ${deb_name} (configures the AMD driver apt repo) ..."
wget -qO /tmp/amdgpu-install.deb "${inst_dir}/${deb_name}" \
    || die "failed to download ${deb_name}."
apt-get install -y /tmp/amdgpu-install.deb || die "failed to install amdgpu-install."
rm -f /tmp/amdgpu-install.deb
apt-get update || warn "apt-get update after adding the AMD repo failed."

# ---------------------------------------------------------------------------
# 5. Install the kernel-mode driver only (amdgpu-dkms + firmware)
# ---------------------------------------------------------------------------
log "Installing amdgpu-dkms ..."
# Note: amdgpu-dkms post-install script may fail in container environments
# due to missing EFI support. We attempt the install and continue even if dpkg
# post-install fails, then manually fix the configuration.
apt-get install -y --no-install-recommends amdgpu-dkms amdgpu-dkms-firmware 2>&1 | grep -v "dpkg: error" || true
apt-get install -y amdgpu-dkms 2>&1 | grep -v "dpkg: error" || true

# Force-configure any packages with broken post-install scripts
log "Force-configuring packages with broken installations..."
dpkg --configure -a --force-all 2>&1 || true

# Verify amdgpu-dkms was at least partially installed
if ! dpkg -l | grep -q "amdgpu-dkms"; then
    die "failed to install amdgpu-dkms. \
List available driver packages with: apt-cache search amdgpu-dkms"
fi

log "amdgpu-dkms package installation completed (post-install script errors suppressed)."

# ---------------------------------------------------------------------------
# 6. Build the DKMS module against the IMAGE kernel (not the build host)
# ---------------------------------------------------------------------------
if command -v dkms >/dev/null 2>&1; then
    log "Building amdgpu DKMS module for kernel ${KVER} ..."
    # `dkms status` differs across versions:
    #   dkms 2.x: "amdgpu, 6.16.13, 6.14.0-36-generic, x86_64: installed"
    #   dkms 3.x: "amdgpu/6.16.13, 6.14.0-36-generic, x86_64: installed"
    # Extract module name (up to first , / or :) + first version-looking token.
    dkms status 2>/dev/null | grep -i amdgpu | while read -r line; do
        mod="$(printf '%s\n' "${line}" | sed -E 's/[,/:].*//' | tr -d ' ')"
        ver="$(printf '%s\n' "${line}" | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1)"
        case "${mod}" in amdgpu*) ;; *) continue ;; esac
        [ -n "${mod}" ] && [ -n "${ver}" ] || continue
        log "  dkms install ${mod}/${ver} -k ${KVER}"
        dkms build   -m "${mod}" -v "${ver}" -k "${KVER}" 2>/dev/null || true
        dkms install -m "${mod}" -v "${ver}" -k "${KVER}" --force 2>/dev/null || true
    done
    # Belt-and-suspenders: autoinstaller pinned to the target kernel.
    dkms autoinstall -k "${KVER}" 2>/dev/null || true
    log "DKMS status:"; dkms status 2>/dev/null || true
else
    warn "dkms not found; relying on apt postinst build."
fi

# ---------------------------------------------------------------------------
# 7. Verify the module landed in the image kernel's module tree
# ---------------------------------------------------------------------------
MODDIR="/lib/modules/${KVER}"
if find "${MODDIR}" -name 'amdgpu.ko*' 2>/dev/null | grep -q .; then
    log "Verified: amdgpu kernel module present under ${MODDIR}."
    find "${MODDIR}" -name 'amdgpu.ko*' 2>/dev/null | sed 's/^/  /'
else
    die "no amdgpu.ko module found under ${MODDIR} -- DKMS build did not produce \
a module for the image kernel. Check that linux-headers-${KVER} and a matching \
gcc are installed."
fi

# ---------------------------------------------------------------------------
# 8. Autoload amdgpu at boot (no blacklist needed -- dkms replaces the in-tree
#    module of the same name)
# ---------------------------------------------------------------------------
log "Configuring amdgpu module autoload ..."
cat > /etc/modules-load.d/amdgpu.conf <<'EOF'
# Managed by CanvOS install-amdgpu-drivers.sh
# Load the AMD GPU driver at boot so the AMD GPU Operator sees a ready driver.
amdgpu
EOF

# ---------------------------------------------------------------------------
# 9. depmod for the target kernel so modprobe resolves amdgpu at boot
# ---------------------------------------------------------------------------
log "Running depmod -a ${KVER} ..."
depmod -a "${KVER}" || warn "depmod reported an error."

# ---------------------------------------------------------------------------
# 10. Rebuild the initrd for the target kernel
# ---------------------------------------------------------------------------
if [ "${AMDGPU_REBUILD_INITRD}" = "true" ] && command -v dracut >/dev/null 2>&1; then
    log "Rebuilding initrd for ${KVER} (dracut) ..."
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
# 11. Cleanup apt caches to keep the image lean
# ---------------------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Done. AMD amdgpu driver (ROCm ${AMDGPU_ROCM_VERSION}) baked in for kernel ${KVER}."
log "Reminder: install the AMD GPU Operator with 'driver.enable=false'."
