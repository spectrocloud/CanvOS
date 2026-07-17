#!/usr/bin/env bash
#
# install-nvidia-drivers.sh
#
# Pre-install the NVIDIA data-center GPU driver and build its kernel modules
# INTO a CanvOS / Kairos Ubuntu base image, so that a node booted from the
# image can run the NVIDIA GPU Operator in a fully air-gapped environment
# WITHOUT any host-side network access and WITHOUT the operator's driver
# container.
#
# WHAT THIS COVERS (OS side only)
# -------------------------------
#   * build toolchain (gcc, make, dkms, kmod, libc headers)
#   * kernel headers that match the kernel shipped in the image
#     (delegated to scripts/install-kernel-headers.sh)
#   * the NVIDIA driver user-space + `nvidia-smi` (nvidia-utils-*-server)
#   * the NVIDIA kernel modules (nvidia, nvidia-uvm, nvidia-modeset,
#     nvidia-drm, nvidia-peermem) built with DKMS against the IMAGE kernel
#   * nouveau blacklist + nvidia module autoload + nvidia-persistenced
#   * nvidia-fabricmanager + libnvidia-nscq for HGX / NVSwitch systems
#     (HGX H100/H200, HGX B200, DGX, GB200) -- required for multi-GPU NVLink
#   * nvidia-imex for GB200 NVL72 multi-node NVLink Sharp (Blackwell)
#
# WHAT THIS DOES *NOT* COVER (ships as container images in your content bundle,
# deployed by the GPU Operator itself):
#   * nvidia-container-toolkit / runtime class
#   * k8s-device-plugin, gpu-feature-discovery, DCGM exporter, MIG manager, ...
#
# At Helm-install time you MUST tell the operator the driver is pre-installed:
#     --set driver.enabled=false
#   (and, if you also pre-install the toolkit below, --set toolkit.enabled=false)
#
# WHY THE DKMS DANCE
# ------------------
# In an Earthly/Docker build `uname -r` is the BUILD HOST kernel, not the kernel
# baked into the image. If we let apt/DKMS build "for the running kernel" the
# modules would target the wrong ABI (or fail). We therefore derive the target
# kernel from /lib/modules (the kernel that will actually boot) and force every
# DKMS build + module install + depmod against THAT kernel.
#
# CONNECTIVITY
# ------------
# This script runs at BUILD time, where the builder has internet. It bakes
# everything into the image. The resulting image needs no network at boot.
#
# TUNABLES (environment variables; all optional)
#   NVIDIA_DRIVER_BRANCH        Driver branch to install (e.g. 550, 570, 580).
#                               Default: 580  (a data-center production branch)
#   NVIDIA_DRIVER_TYPE          "proprietary" | "open"   Default: open
#                               "open" is REQUIRED on Hopper (H100/H200) and
#                               Blackwell (RTX PRO 6000 Blackwell, B100, B200,
#                               GB200) — the closed modules fail with
#                               "RmInitAdapter (0x22:0x56:897)" on those GPUs
#                               and `nvidia-smi` reports "No devices were found".
#                               Also safe on Turing/Ampere/Ada. Override to
#                               "proprietary" only for pre-Turing hardware
#                               (Pascal/Volta).
#   NVIDIA_USE_CUDA_REPO        "true" to add developer.download.nvidia.com CUDA
#                               repo (recommended, has every -server branch).
#                               "false" to use only Ubuntu's own repos.
#                               Default: true
#   NVIDIA_INSTALL_FABRICMANAGER  "true" for NVSwitch/HGX boxes (H100/B200 HGX,
#                               DGX, GB200). Default: true. Harmless on non-
#                               NVSwitch hosts: the unit exits early and stays
#                               inactive; no restart loop, no kernel effect,
#                               ~60-90 MB image cost. Also installs the
#                               matching libnvidia-nscq-<branch> explicitly.
#                               See docs/nvidia-gpu-airgapped.md.
#   NVIDIA_INSTALL_IMEX         "true" to also install nvidia-imex-<branch>,
#                               the Internode Memory Exchange daemon required
#                               for GB200 NVL72 multi-node NVLink Sharp
#                               (Blackwell, driver 570+). Default: true.
#                               Harmless on non-NVL72 boxes: without
#                               /etc/nvidia-imex/nodes_config.cfg the daemon
#                               exits and the unit stays inactive. Best-effort
#                               -- skipped with a warning on branches that
#                               predate IMEX (pre-570).
#   NVIDIA_INSTALL_CONTAINER_TOOLKIT  "true" to ALSO pre-install
#                               nvidia-container-toolkit on the host (then set
#                               toolkit.enabled=false in the operator).
#                               Default: false (operator ships it)
#   NVIDIA_REBUILD_INITRD       "true" to rebuild the initrd so the nouveau
#                               blacklist takes effect in early boot.
#                               Default: true
#
set -u

log()  { echo "[install-nvidia-drivers] $*"; }
warn() { echo "[install-nvidia-drivers] WARNING: $*" >&2; }
die()  { echo "[install-nvidia-drivers] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
NVIDIA_DRIVER_BRANCH="${NVIDIA_DRIVER_BRANCH:-580}"
NVIDIA_DRIVER_TYPE="${NVIDIA_DRIVER_TYPE:-open}"
NVIDIA_USE_CUDA_REPO="${NVIDIA_USE_CUDA_REPO:-true}"
NVIDIA_INSTALL_FABRICMANAGER="${NVIDIA_INSTALL_FABRICMANAGER:-true}"
NVIDIA_INSTALL_IMEX="${NVIDIA_INSTALL_IMEX:-true}"
NVIDIA_INSTALL_CONTAINER_TOOLKIT="${NVIDIA_INSTALL_CONTAINER_TOOLKIT:-false}"
NVIDIA_REBUILD_INITRD="${NVIDIA_REBUILD_INITRD:-true}"

export DEBIAN_FRONTEND=noninteractive

command -v apt-get >/dev/null 2>&1 || die "this script only supports apt-based (Ubuntu/Debian) images."

# ---------------------------------------------------------------------------
# 1. Identify the kernel shipped in the image (NOT the build host kernel)
# ---------------------------------------------------------------------------
KVER="$(printf '%s\n' /lib/modules/* 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -V | tail -1)"
[ -n "${KVER}" ] || die "could not determine target kernel from /lib/modules."
log "Target (image) kernel: ${KVER}"
log "Driver branch: ${NVIDIA_DRIVER_BRANCH} (${NVIDIA_DRIVER_TYPE})"

# ---------------------------------------------------------------------------
# 2. Build toolchain
# ---------------------------------------------------------------------------
log "Installing build toolchain ..."
apt-get update || true
apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg \
    build-essential gcc make \
    dkms kmod libc6-dev pkg-config \
    || die "failed to install build toolchain."

# ---------------------------------------------------------------------------
# 3. Kernel headers matching the image kernel
#    Reuse the repo's ABI-exact / snapshot-aware header installer if present.
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

# DKMS needs /lib/modules/<KVER>/build to point at the headers source tree.
if [ ! -e "/lib/modules/${KVER}/build" ]; then
    # Find the header tree that matches our kernel and symlink it.
    src="$(ls -d /usr/src/linux-headers-${KVER} 2>/dev/null | head -1)"
    if [ -n "${src}" ]; then
        ln -sfn "${src}" "/lib/modules/${KVER}/build"
        log "Linked /lib/modules/${KVER}/build -> ${src}"
    else
        warn "no /usr/src/linux-headers-${KVER}; DKMS build will likely fail."
    fi
fi

# ---------------------------------------------------------------------------
# 4. NVIDIA package repo (CUDA network repo — has every *-server branch)
# ---------------------------------------------------------------------------
if [ "${NVIDIA_USE_CUDA_REPO}" = "true" ]; then
    # Derive the CUDA repo "distro" tag from the image (e.g. 22.04 -> ubuntu2204)
    osid=""; osver=""
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        osid="${ID:-ubuntu}"
        osver="${VERSION_ID:-22.04}"
    fi
    distro="${osid}$(echo "${osver}" | tr -d '.')"   # ubuntu2204, ubuntu2004, ...
    case "$(uname -m)" in
        x86_64)  cudaarch="x86_64" ;;
        aarch64) cudaarch="sbsa"   ;;
        *)       cudaarch="x86_64" ;;
    esac
    repo_base="https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${cudaarch}"
    log "Adding NVIDIA CUDA repo: ${repo_base}"
    if wget -qO /tmp/cuda-keyring.deb "${repo_base}/cuda-keyring_1.1-1_all.deb"; then
        dpkg -i /tmp/cuda-keyring.deb || warn "cuda-keyring install failed."
        rm -f /tmp/cuda-keyring.deb
        apt-get update || warn "apt-get update after adding CUDA repo failed."
    else
        warn "could not download cuda-keyring; falling back to Ubuntu repos."
    fi
fi

# ---------------------------------------------------------------------------
# 5. Choose driver packages
#    Headless server packages (no Xorg / GUI). nvidia-utils gives nvidia-smi.
# ---------------------------------------------------------------------------
if [ "${NVIDIA_DRIVER_TYPE}" = "open" ]; then
    HEADLESS_PKG="nvidia-headless-${NVIDIA_DRIVER_BRANCH}-server-open"
else
    HEADLESS_PKG="nvidia-headless-${NVIDIA_DRIVER_BRANCH}-server"
fi
UTILS_PKG="nvidia-utils-${NVIDIA_DRIVER_BRANCH}-server"

log "Installing NVIDIA driver packages: ${HEADLESS_PKG} ${UTILS_PKG}"
if ! apt-get install -y --no-install-recommends "${HEADLESS_PKG}" "${UTILS_PKG}"; then
    warn "'${HEADLESS_PKG}' not available; retrying with generic (non-server) branch."
    if [ "${NVIDIA_DRIVER_TYPE}" = "open" ]; then
        HEADLESS_PKG="nvidia-headless-${NVIDIA_DRIVER_BRANCH}-open"
    else
        HEADLESS_PKG="nvidia-headless-${NVIDIA_DRIVER_BRANCH}"
    fi
    UTILS_PKG="nvidia-utils-${NVIDIA_DRIVER_BRANCH}"
    apt-get install -y --no-install-recommends "${HEADLESS_PKG}" "${UTILS_PKG}" \
        || die "failed to install NVIDIA driver packages for branch ${NVIDIA_DRIVER_BRANCH}. \
Check available branches with: apt-cache search 'nvidia-headless-.*-server'"
fi

# ---------------------------------------------------------------------------
# 6. Build the DKMS modules against the IMAGE kernel (not the build host)
# ---------------------------------------------------------------------------
# The apt postinst runs `dkms autoinstall`, which only builds for kernels that
# have headers present -- i.e. our target kernel, since the build host kernel's
# headers are absent in the image. We still force it explicitly to be safe.
if command -v dkms >/dev/null 2>&1; then
    log "Building NVIDIA DKMS modules for kernel ${KVER} ..."
    # Explicitly (re)build every registered nvidia dkms module for the target.
    # `dkms status` output differs across versions:
    #   dkms 2.x: "nvidia, 580.159.03, 6.14.0-36-generic, x86_64: installed"
    #   dkms 3.x: "nvidia/580.159.03, 6.14.0-36-generic, x86_64: installed"
    # Extract the module name (up to the first , / or :) and the first
    # version-looking token, which works for both formats.
    dkms status 2>/dev/null | grep -i nvidia | while read -r line; do
        mod="$(printf '%s\n' "${line}" | sed -E 's/[,/:].*//' | tr -d ' ')"
        ver="$(printf '%s\n' "${line}" | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1)"
        case "${mod}" in nvidia*) ;; *) continue ;; esac
        [ -n "${mod}" ] && [ -n "${ver}" ] || continue
        log "  dkms install ${mod}/${ver} -k ${KVER}"
        dkms build   -m "${mod}" -v "${ver}" -k "${KVER}" 2>/dev/null || true
        dkms install -m "${mod}" -v "${ver}" -k "${KVER}" --force 2>/dev/null || true
    done
    # Belt-and-suspenders: try the autoinstaller pinned to the target kernel
    # (ignored gracefully by older dkms that lack the -k flag).
    dkms autoinstall -k "${KVER}" 2>/dev/null || true
    log "DKMS status:"; dkms status 2>/dev/null || true
else
    warn "dkms not found; relying on apt postinst build."
fi

# ---------------------------------------------------------------------------
# 7. Verify the modules actually landed in the image kernel's module tree
# ---------------------------------------------------------------------------
MODDIR="/lib/modules/${KVER}"
if ls "${MODDIR}"/updates/dkms/nvidia*.ko* >/dev/null 2>&1 || \
   ls "${MODDIR}"/kernel/drivers/video/nvidia*.ko* >/dev/null 2>&1 || \
   find "${MODDIR}" -name 'nvidia*.ko*' 2>/dev/null | grep -q .; then
    log "Verified: nvidia kernel modules present under ${MODDIR}."
    find "${MODDIR}" -name 'nvidia*.ko*' 2>/dev/null | sed 's/^/  /'
else
    die "no nvidia*.ko modules found under ${MODDIR} -- DKMS build did not \
produce modules for the image kernel. Check that linux-headers-${KVER} and a \
matching gcc are installed."
fi

# ---------------------------------------------------------------------------
# 8. NVIDIA Fabric Manager + libnvidia-nscq + nvlsm (HGX / NVSwitch systems)
#    Required on HGX H100/H200, HGX B200, DGX, GB200 for multi-GPU NVLink.
#    libnvidia-nscq-<branch> is a fabricmanager dep and gets pulled in
#    transitively -- listed explicitly so the install fails loudly if the
#    CUDA repo ever drops the auto-dep.
#
#    NVIDIA 570+ ships the FM unit with ExecStart wrapped in
#    /usr/share/nvidia/fabricmanager/nvidia-fabricmanager-start.sh, which
#    probes `ibstat` (infiniband-diags) and `nvlsm` (NVIDIA Subnet Manager)
#    before invoking nv-fabricmanager -- needed so the NVLink subnet is up
#    on GB200 NVL72. Both binaries must be present or the unit dies:
#       "ibstat command not found! Please install ibstat."
#       "nvlsm command not found! Please install nvlsm."
#    Empirically the wrapper succeeds on standalone HGX topologies once
#    both are installed (verified on HGX with nvlsm 2025.10.14-1 from the
#    NVIDIA CUDA repo we already added in step 4), so we install them
#    alongside FM and let the vendor wrapper stay in charge.
#
#    Package sources: nvlsm ships in the CUDA repo under an unversioned
#    package name (not nvlsm-<branch>). infiniband-diags is Ubuntu-native.
#    On non-NVSwitch hosts nv-fabricmanager still exits "No NvSwitch found"
#    and the unit stays inactive; no kernel side effect, no restart loop.
# ---------------------------------------------------------------------------
if [ "${NVIDIA_INSTALL_FABRICMANAGER}" = "true" ]; then
    FM_PKG="nvidia-fabricmanager-${NVIDIA_DRIVER_BRANCH}"
    NSCQ_PKG="libnvidia-nscq-${NVIDIA_DRIVER_BRANCH}"
    log "Installing ${FM_PKG} + ${NSCQ_PKG} + nvlsm + infiniband-diags ..."
    if apt-get install -y --no-install-recommends \
            "${FM_PKG}" "${NSCQ_PKG}" nvlsm infiniband-diags; then
        systemctl enable nvidia-fabricmanager.service 2>/dev/null || true
    else
        warn "could not install ${FM_PKG} / ${NSCQ_PKG} / nvlsm / infiniband-diags; skipping fabric manager."
    fi
fi

# ---------------------------------------------------------------------------
# 8b. NVIDIA IMEX -- Internode Memory Exchange daemon
#     Required for GB200 NVL72 multi-node NVLink Sharp (Blackwell, driver
#     570+). Not needed for single-node HGX B200 or HGX H100. Package is
#     part of the CUDA repo; older driver branches (pre-570) do not publish
#     it, so this is best-effort. On single-node boxes the daemon has no
#     /etc/nvidia-imex/nodes_config.cfg and exits cleanly -- unit stays
#     inactive, ~10-20 MB image cost.
# ---------------------------------------------------------------------------
if [ "${NVIDIA_INSTALL_IMEX}" = "true" ]; then
    IMEX_PKG="nvidia-imex-${NVIDIA_DRIVER_BRANCH}"
    log "Installing ${IMEX_PKG} (GB200 NVL72 multi-node NVLink Sharp) ..."
    if apt-get install -y --no-install-recommends "${IMEX_PKG}"; then
        systemctl enable nvidia-imex.service 2>/dev/null || true
    else
        warn "${IMEX_PKG} not available (branch ${NVIDIA_DRIVER_BRANCH} may predate IMEX -- 570+ only). Skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 9. Optional: nvidia-container-toolkit on the host
#    (default OFF -- the GPU Operator ships and configures the toolkit)
# ---------------------------------------------------------------------------
if [ "${NVIDIA_INSTALL_CONTAINER_TOOLKIT}" = "true" ]; then
    log "Installing nvidia-container-toolkit on host ..."
    install -d -m 0755 /usr/share/keyrings
    if curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; then
        curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
            > /etc/apt/sources.list.d/nvidia-container-toolkit.list
        apt-get update && apt-get install -y --no-install-recommends nvidia-container-toolkit \
            || warn "nvidia-container-toolkit install failed."
    else
        warn "could not fetch nvidia-container-toolkit gpg key; skipping."
    fi
fi

# ---------------------------------------------------------------------------
# 10. Host module configuration: blacklist nouveau + autoload nvidia
# ---------------------------------------------------------------------------
log "Configuring nouveau blacklist and nvidia module autoload ..."
cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
# Managed by CanvOS install-nvidia-drivers.sh
blacklist nouveau
blacklist lbm-nouveau
options nouveau modeset=0
alias nouveau off
alias lbm-nouveau off
EOF

cat > /etc/modules-load.d/nvidia.conf <<'EOF'
# Managed by CanvOS install-nvidia-drivers.sh
# Load the NVIDIA stack at boot so the GPU Operator sees a ready driver.
# nvidia_drm is intentionally omitted: it grabs KMS/DRM and on headless GPU
# nodes can wedge early boot. It loads on demand if anything wants it.
nvidia
nvidia_uvm
nvidia_modeset
EOF

# NVIDIA driver run-time module options recommended for datacenter use:
#   NVreg_OpenRmEnableUnsupportedGpus is only relevant for the open modules.
cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# Managed by CanvOS install-nvidia-drivers.sh
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

# Enable the persistence daemon (recommended for datacenter GPUs).
systemctl enable nvidia-persistenced.service 2>/dev/null || true

# ---------------------------------------------------------------------------
# 11. depmod for the target kernel so modprobe can resolve nvidia at boot
# ---------------------------------------------------------------------------
log "Running depmod -a ${KVER} ..."
depmod -a "${KVER}" || warn "depmod reported an error."

# ---------------------------------------------------------------------------
# 12. Make sure the initrd honors the nouveau blacklist and does NOT ship
#     nouveau.ko. The /etc/modprobe.d/blacklist-nouveau.conf we wrote above
#     lives on the rootfs and is only consulted AFTER switchroot; by then
#     nouveau has already been auto-loaded by initramfs udev on modern
#     NVIDIA data-center GPUs (Ada/Hopper/Blackwell), where nouveau's GSP-RM
#     support hangs on device init and stalls udev-settle forever.
#
#     Fix: write a dracut.conf.d snippet so BOTH this script's dracut
#     rebuild AND the later Earthfile-driven dracut rebuild produce an
#     initrd that (a) omits nouveau entirely and (b) carries the modprobe
#     blacklist file, so initramfs modprobe honors it too.
# ---------------------------------------------------------------------------
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/95-blacklist-nouveau.conf <<'EOF'
# Managed by CanvOS install-nvidia-drivers.sh
omit_drivers+=" nouveau lbm-nouveau "
install_items+=" /etc/modprobe.d/blacklist-nouveau.conf "
EOF

# ---------------------------------------------------------------------------
# 12b. Rebuild the initrd so the nouveau blacklist applies in early boot
# ---------------------------------------------------------------------------
if [ "${NVIDIA_REBUILD_INITRD}" = "true" ] && command -v dracut >/dev/null 2>&1; then
    log "Rebuilding initrd for ${KVER} (dracut) ..."
    if dracut -f "/boot/initrd-${KVER}" "${KVER}"; then
        ln -sf "initrd-${KVER}" /boot/initrd
    else
        warn "dracut initrd rebuild failed; nouveau blacklist still applies post-switchroot."
    fi
elif [ "${NVIDIA_REBUILD_INITRD}" = "true" ] && command -v update-initramfs >/dev/null 2>&1; then
    log "Rebuilding initramfs for ${KVER} (update-initramfs) ..."
    update-initramfs -u -k "${KVER}" || warn "update-initramfs failed."
fi

# ---------------------------------------------------------------------------
# 13. Cleanup apt caches to keep the image lean
# ---------------------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Done. NVIDIA driver ${NVIDIA_DRIVER_BRANCH} (${NVIDIA_DRIVER_TYPE}) baked in for kernel ${KVER}."
log "Reminder: install the GPU Operator with 'driver.enabled=false'."
if [ "${NVIDIA_INSTALL_CONTAINER_TOOLKIT}" = "true" ]; then
    log "Reminder: you pre-installed the container toolkit -> also set 'toolkit.enabled=false'."
fi
