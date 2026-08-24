#!/usr/bin/env bash
# Ubuntu STIG remediation wrapper: logs like rhel-stig/stig-remediate.sh and keeps
# the SCAP datastream under /var/log/stig-remediation for post-install oscap scans.
set -uo pipefail

LOG_DIR="/var/log/stig-remediation"
mkdir -p "$LOG_DIR"

DEBUG_LOG="$LOG_DIR/debug.log"
SUMMARY_LOG="$LOG_DIR/summary.log"

print_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"
}

log_exit_status() {
    local exit_code=$?
    local status_msg=""
    if [ "$exit_code" -eq 0 ]; then
        status_msg="SUCCESS"
    else
        status_msg="FAILED (exit code: $exit_code)"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script execution $status_msg" >> "$SUMMARY_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Check $DEBUG_LOG for detailed logs" >> "$SUMMARY_LOG"
}

trap log_exit_status EXIT

REMEDIATION_SCRIPT="${STIG_REMEDIATION_SCRIPT:-/tmp/fix.sh}"

echo "Starting Ubuntu STIG remediation..."
print_debug "Starting Ubuntu STIG remediation..."
print_debug "Log directory: $LOG_DIR"

if [ ! -f "$REMEDIATION_SCRIPT" ]; then
    print_debug "ERROR: remediation script not found at $REMEDIATION_SCRIPT"
    echo "ERROR: remediation script not found at $REMEDIATION_SCRIPT" >&2
    echo "Check $DEBUG_LOG for details" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# OpenSCAP scanner: package "openscap-scanner". SCAP Security Guide *datastreams* on
# Ubuntu are in "ssg-debderived" (not a binary package named scap-security-guide; that
# name is the source package only).
apt_sources_have_universe() {
    shopt -s nullglob
    local f
    for f in /etc/apt/sources.list.d/*.sources; do
        if grep -qE '^Components:.*[[:space:]]universe([[:space:]]|$)' "$f" 2>/dev/null; then
            shopt -u nullglob
            return 0
        fi
    done
    local scan_files=(/etc/apt/sources.list)
    for f in /etc/apt/sources.list.d/*.list; do
        scan_files+=("$f")
    done
    for f in "${scan_files[@]}"; do
        [ -f "$f" ] || continue
        if grep -vE '^[[:space:]]*#' "$f" | grep -qE '^deb[[:space:]].*[[:space:]]universe([[:space:]]|$)'; then
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

prepare_apt_universe_for_openscap() {
    [ -f /etc/os-release ] && . /etc/os-release
    local c="${VERSION_CODENAME:-}"
    [ -n "$c" ] || return 0

    if apt_sources_have_universe; then
        print_debug "APT sources already reference universe; skipping extra repo lines"
        return 0
    fi

    print_debug "Enabling Ubuntu universe repository (required for openscap-scanner / ssg-debderived)..."

    local f
    for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu-ports.sources; do
        if [ -f "$f" ] && grep -q '^Components:' "$f" && ! grep -qE '^Components:.*[[:space:]]universe([[:space:]]|$)' "$f"; then
            sed -i '/^Components:/ {/universe/! s/$/ universe/}' "$f"
            return 0
        fi
    done

    local mirror
    shopt -s nullglob
    local deb_lines
    deb_lines=$(grep -hE '^deb[[:space:]]+' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | head -1 || true)
    shopt -u nullglob
    mirror=$(echo "$deb_lines" | awk '{print $2}')
    [ -n "$mirror" ] || mirror="http://archive.ubuntu.com/ubuntu"
    local drop=/etc/apt/sources.list.d/canvos-stig-universe.list
    {
        printf 'deb %s %s universe\n' "$mirror" "$c"
        printf 'deb %s %s-updates universe\n' "$mirror" "$c"
    } >"$drop"
}

# Pick Ubuntu SSG datastream: release-specific paths first (so Noble does not pick 22.04 from
# ssg-debderived when /tmp/stig-static holds an upstream 24.04 DS), then generic static, then apt.
pick_ssg_ds_path() {
    local static dir base f
    static=/tmp/stig-static
    dir=/usr/share/xml/scap/ssg/content
    base=""

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "${VERSION_ID:-}" in
            24.04) base=ssg-ubuntu2404 ;;
            22.04) base=ssg-ubuntu2204 ;;
            20.04) base=ssg-ubuntu2004 ;;
        esac
    fi

    shopt -s nullglob
    if [ -n "$base" ]; then
        for f in "$static/${base}-ds.xml" "$static/${base}-ds-1.2.xml" \
                 "$dir/${base}-ds.xml" "$dir/${base}-ds-1.2.xml"; do
            if [ -f "$f" ]; then
                printf '%s' "$f"
                shopt -u nullglob
                return 0
            fi
        done
    fi

    for f in "$static"/ssg-ubuntu*-ds.xml "$static"/ssg-ubuntu*-ds-1.2.xml; do
        if [ -f "$f" ]; then
            printf '%s' "$f"
            shopt -u nullglob
            return 0
        fi
    done

    local candidates=("$dir"/ssg-ubuntu*-ds.xml)
    if [ "${#candidates[@]}" -gt 0 ]; then
        printf '%s\n' "${candidates[@]}" | sort -V | tail -1
        shopt -u nullglob
        return 0
    fi
    shopt -u nullglob
    return 1
}

# Noble's ssg-debderived often lags fix.sh; bundle 24.04 STIG at benchmark 0.1.78 (see 24.04/fix.sh).
fetch_ssg_ubuntu2404_ds_upstream() {
    local dest_dir="/tmp/stig-static"
    local dest="$dest_dir/ssg-ubuntu2404-ds.xml"
    local ver="${STIG_SSG_VENDOR_VERSION:-0.1.78}"
    local url="https://github.com/ComplianceAsCode/content/releases/download/v${ver}/scap-security-guide-${ver}.tar.gz"
    local work found

    command -v curl >/dev/null 2>&1 || {
        print_debug "curl not available; cannot fetch upstream scap-security-guide ${ver}"
        return 1
    }

    mkdir -p "$dest_dir"
    work=$(mktemp -d)
    print_debug "Fetching ComplianceAsCode scap-security-guide ${ver} (${url}) for ssg-ubuntu2404-ds.xml..."
    if ! curl -fsSL "$url" | tar -xz -C "$work" 2>/dev/null; then
        print_debug "Failed to download or extract upstream tarball (offline or URL change?)"
        rm -rf "$work"
        return 1
    fi
    found=$(find "$work" -type f -name 'ssg-ubuntu2404-ds.xml' 2>/dev/null | head -1)
    if [ -z "$found" ] || [ ! -f "$found" ]; then
        print_debug "ssg-ubuntu2404-ds.xml not present in extracted ${ver} tarball"
        rm -rf "$work"
        return 1
    fi
    cp "$found" "$dest"
    rm -rf "$work"
    print_debug "Wrote upstream datastream to $dest (matches fix.sh benchmark ${ver})"
    return 0
}

ensure_ubuntu2404_ds_when_apt_lags() {
    [ -f /etc/os-release ] || return 0
    # shellcheck source=/dev/null
    . /etc/os-release
    [ "${VERSION_ID:-}" = "24.04" ] || return 0

    local d=/usr/share/xml/scap/ssg/content
    local s=/tmp/stig-static
    if [ -f "$d/ssg-ubuntu2404-ds.xml" ] || [ -f "$d/ssg-ubuntu2404-ds-1.2.xml" ] \
        || [ -f "$s/ssg-ubuntu2404-ds.xml" ] || [ -f "$s/ssg-ubuntu2404-ds-1.2.xml" ]; then
        return 0
    fi

    if [ "${STIG_FETCH_UPSTREAM_SSG:-1}" != "1" ]; then
        print_debug "STIG_FETCH_UPSTREAM_SSG is not 1; skipping upstream fetch for 24.04 DS (use /tmp/stig-static or allow 22.04 fallback)."
        return 0
    fi

    fetch_ssg_ubuntu2404_ds_upstream \
        || print_debug "Upstream fetch failed; pick_ssg_ds_path may fall back to ssg-ubuntu2204-ds.xml from ssg-debderived."
}

build_openscap_pkg_list() {
    local pkgs=()
    if apt-cache show ssg-debderived >/dev/null 2>&1; then
        pkgs+=(ssg-debderived)
    elif apt-cache show scap-security-guide >/dev/null 2>&1; then
        pkgs+=(scap-security-guide)
    fi
    if apt-cache show openscap-scanner >/dev/null 2>&1; then
        pkgs+=(openscap-scanner)
    fi
    printf '%s\n' "${pkgs[@]}"
}

install_openscap_from_cache_or_empty() {
    local _stig_pkgs
    mapfile -t _stig_pkgs < <(build_openscap_pkg_list)
    if [ "${#_stig_pkgs[@]}" -eq 0 ]; then
        return 1
    fi
    apt-get install -y --no-install-recommends "${_stig_pkgs[@]}" \
        || { print_debug "ERROR: apt-get install failed for: ${_stig_pkgs[*]}"; exit 1; }
    return 0
}

ensure_oscap_and_content() {
    if command -v oscap >/dev/null 2>&1 && pick_ssg_ds_path >/dev/null; then
        print_debug "oscap and SSG datastream already on image ($(pick_ssg_ds_path))"
        return 0
    fi

    print_debug "Installing OpenSCAP / SSG content if published for this release (ssg-debderived, openscap-scanner)..."
    rm -f /etc/apt/sources.list.d/canvos-stig-universe.list

    apt-get update || { print_debug "ERROR: apt-get update failed"; exit 1; }

    if install_openscap_from_cache_or_empty; then
        return 0
    fi

    print_debug "Packages not in apt index after first update; enabling universe (if needed) and refreshing..."
    prepare_apt_universe_for_openscap
    apt-get update || { print_debug "ERROR: apt-get update failed"; exit 1; }

    if install_openscap_from_cache_or_empty; then
        return 0
    fi

    print_debug "Forcing full apt lists refresh (clear /var/lib/apt/lists)..."
    rm -rf /var/lib/apt/lists/*
    apt-get update || { print_debug "ERROR: apt-get update failed after lists purge"; exit 1; }

    if install_openscap_from_cache_or_empty; then
        return 0
    fi

    print_debug "apt-cache policy ssg-debderived openscap-scanner:"
    apt-cache policy ssg-debderived openscap-scanner 2>&1 | while read -r line; do print_debug "  $line"; done || true
    print_debug "No ssg-debderived/openscap-scanner in apt for this release (e.g. 22.04). Remediation still runs; add /tmp/stig-static/*.xml in the image build or scan from a host with SSG content."
}

ensure_oscap_and_content

ensure_ubuntu2404_ds_when_apt_lags

STIG_PROFILE="xccdf_org.ssgproject.content_profile_stig"
STIG_DS_COPY=""
STIG_XCCDF=""
if ds_src=$(pick_ssg_ds_path); then
    STIG_XCCDF="$ds_src"
    echo "Using STIG datastream: $STIG_XCCDF"
    echo "Using STIG profile: $STIG_PROFILE"
    print_debug "Using STIG datastream: $STIG_XCCDF"
    print_debug "Using STIG profile: $STIG_PROFILE"
    STIG_DS_COPY="$LOG_DIR/$(basename "$STIG_XCCDF")"
    cp "$STIG_XCCDF" "$STIG_DS_COPY"
    print_debug "Copied STIG datastream to $STIG_DS_COPY for post-boot compliance scans"
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        if [ "${VERSION_ID:-}" = "24.04" ] && [[ "$(basename "$STIG_XCCDF")" == *"2204"* ]]; then
            print_debug "NOTE: Using ssg-ubuntu2204 datastream on 24.04. Ubuntu-packaged 22.04 datastreams usually do NOT include the DISA STIG XCCDF profile (only CIS/standard-style profiles), so 'oscap xccdf eval --profile ...stig' will fail. Rebuild with upstream fetch (default STIG_FETCH_UPSTREAM_SSG=1) or place ssg-ubuntu2404-ds.xml in /tmp/stig-static. Check profiles: oscap info --profiles <ds.xml>"
        fi
    fi
else
    print_debug "No ssg-ubuntu*-ds.xml found under /usr/share/xml/scap/ssg/content/ or /tmp/stig-static/ after installs."
fi

if ! command -v oscap >/dev/null 2>&1; then
    print_debug "NOTE: oscap not on PATH (optional on releases without openscap-scanner); install openscap-scanner where available to eval the datastream on-node."
fi

REMEDIATION_LOG="$LOG_DIR/remediation.log"
print_debug "Running remediation script: $REMEDIATION_SCRIPT"
print_debug "Remediation log: $REMEDIATION_LOG"

set +e
bash -x "$REMEDIATION_SCRIPT" 2>&1 | tee "$REMEDIATION_LOG"
REMEDIATION_EXIT_CODE="${PIPESTATUS[0]}"
set -uo pipefail

if [ "$REMEDIATION_EXIT_CODE" -eq 0 ]; then
    print_debug "STIG remediation completed successfully"
else
    print_debug "STIG remediation completed with non-zero exit ($REMEDIATION_EXIT_CODE); see $REMEDIATION_LOG"
fi

REMEDIATION_SCRIPT_SAVED="$LOG_DIR/stig-fix.sh"
cp "$REMEDIATION_SCRIPT" "$REMEDIATION_SCRIPT_SAVED"
print_debug "Saved remediation script to $REMEDIATION_SCRIPT_SAVED"
chmod +r "$REMEDIATION_SCRIPT_SAVED" 2>/dev/null || true

print_debug "STIG remediation logs: $LOG_DIR"
print_debug "  $DEBUG_LOG (debug)"
print_debug "  $REMEDIATION_LOG (remediation stdout/stderr, bash -x)"
if [ -n "$STIG_DS_COPY" ]; then
    print_debug "  $STIG_DS_COPY (datastream for oscap xccdf eval on the host)"
fi

exit 0
