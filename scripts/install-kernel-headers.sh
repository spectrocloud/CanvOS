#!/usr/bin/env bash
#
# install-kernel-headers.sh
#
# Install the Linux kernel headers that match the kernel shipped in the
# (Kairos) base image, for Ubuntu/Debian (apt) based provider images.
#
# WHY THIS EXISTS
# ---------------
# The base image ships a fixed kernel ABI (e.g. 6.14.0-36-generic), but
# Ubuntu's `*-updates` pocket only ever keeps the *current* HWE kernel ABI in
# the live mirrors. When Ubuntu rotates the ABI (e.g. -36 -> -37), the headers
# matching the base image's kernel disappear from the live mirror while the
# base image still ships the old modules. An exact-version
# `apt-get install linux-headers-<kernel>` then fails with
# "no installation candidate" (apt exit code 100).
#
# This script is intentionally generic: it derives everything from the running
# image at build time and hardcodes NO kernel version, ABI, Ubuntu release, or
# snapshot date, so it keeps working across every future kernel bump.
#
# STRATEGY (in order, first success wins)
#   1. Already present in /usr/src        -> nothing to do.
#   2. Exact match from the live mirrors   -> fast path (fresh mirror).
#   3. Exact match from snapshot.ubuntu.com -> Ubuntu's immutable archive keeps
#      every historical package, so we can always recover the ABI-matching
#      headers even after the live mirror rotated them out.
#   4. Best-effort fallback (closest ABI, then the linux-headers-generic
#      metapackage) with a loud warning, but WITHOUT failing the build -- this
#      mirrors the behaviour the SUSE/RHEL branches already use.
#
set -u

log() { echo "[install-kernel-headers] $*"; }

# --- 1. Identify the kernel shipped in the image -----------------------------
# Pick the highest-versioned kernel under /lib/modules (same logic the Earthfile
# uses elsewhere) so we install headers for the kernel that will actually run.
kernel="$(printf '%s\n' /lib/modules/* | xargs -n1 basename | sort -V | tail -1)"
if [ -z "${kernel}" ]; then
    log "Could not determine kernel from /lib/modules; nothing to do."
    exit 0
fi
log "Target kernel: ${kernel}"

# Already have matching headers? Done.
if ls /usr/src 2>/dev/null | grep -q "linux-headers-${kernel}"; then
    log "Headers for ${kernel} already present in /usr/src; skipping."
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# --- 2. Fast path: exact match from the currently configured repos -----------
apt-get update || true
if apt-get install -y "linux-headers-${kernel}"; then
    log "Installed linux-headers-${kernel} from the live mirror."
    exit 0
fi
log "linux-headers-${kernel} not available in the live mirror; trying snapshot.ubuntu.com ..."

# --- 3. Exact match from Ubuntu's immutable snapshot archive -----------------
# The matching headers package shares the exact version of the already-installed
# kernel image package (e.g. linux-image-6.14.0-36-generic -> 6.14.0-36.36),
# so we pin to that version to avoid pulling a mismatched ABI.
hdr_version="$(dpkg-query -W -f='${Version}' "linux-image-${kernel}" 2>/dev/null || true)"

# Ubuntu release codename (noble, jammy, ...) read from the image itself.
codename=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-}"
fi

# Candidate snapshot timestamps, most-likely first. The kernel modules dir was
# created when that kernel was current, so a snapshot at-or-after that moment
# still carries the matching headers. snapshot.ubuntu.com serves the nearest
# snapshot at-or-before the requested timestamp, so a slightly-later stamp is
# safe. We also try a few coarse look-backs as a safety net.
snap_candidates=""
if mtime="$(date -u -r "/lib/modules/${kernel}" +%Y%m%dT%H%M%SZ 2>/dev/null)"; then
    snap_candidates="${mtime}"
fi
# Coarse fallbacks relative to build time (older = more likely to still hold the
# rotated-out ABI). Skipped automatically if `date` math is unavailable.
for days in 7 21 60 120; do
    if ts="$(date -u -d "-${days} days" +%Y%m%dT%H%M%SZ 2>/dev/null)"; then
        snap_candidates="${snap_candidates} ${ts}"
    fi
done

snapshot_install() {
    local ts="$1"
    local list="/etc/apt/sources.list.d/kernel-headers-snapshot.list"
    local keyring="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
    local signed=""
    [ -r "${keyring}" ] && signed="[signed-by=${keyring}]"

    {
        echo "deb ${signed} https://snapshot.ubuntu.com/ubuntu/${ts} ${codename} main"
        echo "deb ${signed} https://snapshot.ubuntu.com/ubuntu/${ts} ${codename}-updates main"
        echo "deb ${signed} https://snapshot.ubuntu.com/ubuntu/${ts} ${codename}-security main"
    } > "${list}"

    local ok=1
    if apt-get -o Acquire::Check-Valid-Until=false update; then
        if [ -n "${hdr_version}" ]; then
            apt-get install -y "linux-headers-${kernel}=${hdr_version}" && ok=0
        fi
        # Fall back to an unpinned exact-name install if the pinned version
        # is not in this particular snapshot.
        [ "${ok}" -ne 0 ] && apt-get install -y "linux-headers-${kernel}" && ok=0
    fi

    rm -f "${list}"
    apt-get -o Acquire::Check-Valid-Until=false update || true
    return "${ok}"
}

if [ -n "${codename}" ]; then
    for ts in ${snap_candidates}; do
        log "Trying snapshot ${ts} for linux-headers-${kernel} (${hdr_version:-any}) ..."
        if snapshot_install "${ts}"; then
            log "Installed linux-headers-${kernel} from snapshot ${ts}."
            exit 0
        fi
    done
else
    log "Could not determine Ubuntu codename; skipping snapshot lookup."
fi

# --- 4. Best-effort fallback (never hard-fail) -------------------------------
# At this point we could not get ABI-exact headers. Try the closest available
# headers for the same X.Y.Z-ABI line, then the generic metapackage. A mismatch
# is not useful for building modules against the running kernel, so we warn
# loudly but, like the SUSE/RHEL branches, do not fail the build.
abi_prefix="$(echo "${kernel}" | sed -E 's/-[a-z]+$//')"   # e.g. 6.14.0-36
closest="$(apt-cache search --names-only "^linux-headers-${abi_prefix%-*}-[0-9]+-generic$" 2>/dev/null \
            | awk '{print $1}' | sort -V | tail -1)"
if [ -n "${closest}" ] && apt-get install -y "${closest}"; then
    log "WARNING: exact headers for ${kernel} unavailable; installed closest match ${closest} (ABI may not match the running kernel)."
    exit 0
fi
if apt-get install -y linux-headers-generic; then
    log "WARNING: exact headers for ${kernel} unavailable; installed linux-headers-generic (ABI may not match the running kernel)."
    exit 0
fi

log "WARNING: could not install any linux-headers for ${kernel}; continuing build without kernel headers."
exit 0
