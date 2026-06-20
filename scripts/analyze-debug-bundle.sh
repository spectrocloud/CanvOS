#!/bin/bash
#
# analyze-debug-bundle.sh
#
# Offline, rule-based root-cause analyzer for the debug bundles produced by
# the "Palette Edge Debug Install" menu entry (collect-debug-bundle.sh).
#
# Runs on an engineer's laptop - no network, no dependencies beyond coreutils,
# tar and grep. Point it at a bundle (a .tar.gz or an already-extracted dir)
# and it prints a ranked list of likely root causes with the evidence lines.
#
# Usage:
#   scripts/analyze-debug-bundle.sh palette-debug-<host>-<ts>.tar.gz
#   scripts/analyze-debug-bundle.sh /path/to/extracted/dir
#
# Each "signature" below is a self-contained block: add a new failure pattern
# by copying a check_* function and registering it in main().

set -u

# ----------------------------------------------------------------------------
# Setup: resolve input into a directory $D we can grep over.
# ----------------------------------------------------------------------------
INPUT="${1:-}"
if [ -z "$INPUT" ]; then
    echo "usage: $0 <bundle.tar.gz | extracted-dir>" >&2
    exit 2
fi

CLEANUP=""
if [ -d "$INPUT" ]; then
    D="$INPUT"
elif [ -f "$INPUT" ]; then
    D="$(mktemp -d /tmp/palette-debug-analyze.XXXXXX)"
    CLEANUP="$D"
    echo "Extracting $INPUT ..."
    tar -xzf "$INPUT" -C "$D" || { echo "ERROR: cannot extract $INPUT" >&2; exit 2; }
    # Bundle has a single top-level dir; descend into it if so.
    inner="$(find "$D" -maxdepth 1 -mindepth 1 -type d | head -n1)"
    [ -n "$inner" ] && D="$inner"
else
    echo "ERROR: '$INPUT' is neither a file nor a directory" >&2
    exit 2
fi
trap '[ -n "$CLEANUP" ] && rm -rf "$CLEANUP"' EXIT

# Findings accumulate here: "<severity>|<title>|<evidence>".
# Evidence may be multi-line; newlines are encoded so each finding stays on a
# single line through the sort pipeline, then decoded at print time.
FINDINGS=()
add() {
    local ev="${3//$'\n'/~~NL~~}"
    FINDINGS+=("$1|$2|$ev")
}

# g <regex> <files...> : grep -iE across files that exist, return matched lines.
g() {
    local re="$1"; shift
    local files=()
    for f in "$@"; do
        # allow globs / dirs
        if [ -d "$f" ]; then files+=("$f"); fi
        if [ -e "$f" ]; then files+=("$f"); fi
    done
    [ ${#files[@]} -eq 0 ] && return 1
    grep -rihE "$re" "${files[@]}" 2>/dev/null | head -n 6
}

J="$D/journal-full.txt $D/journal-errors.txt $D/kairos-stylus.txt"
DMESG="$D/dmesg.txt $D/storage-dmesg.txt"
STORAGE="$D/block-lsblk.txt $D/block-lsblk-p.txt $D/block-blkid.txt $D/nvme-list.txt $D/iscsi-sessions.txt $D/pci-devices.txt $D/scsi-devices.txt"
NET="$D/net-ip-addr.txt $D/net-ip-route.txt $D/net-dns.txt"

# ----------------------------------------------------------------------------
# Signature checks
# ----------------------------------------------------------------------------

# 1. Install target disk not found / no eligible disk.
check_no_disk() {
    local ev
    ev="$(g "no (target )?(disk|device) found|could not find.*device|no eligible|target device.* not|install device.* (not|empty)|failed to find install" $J)"
    if [ -n "$ev" ]; then
        add HIGH "Install target disk not found - installer could not select a device" "$ev"
    fi
    # Corroborate: only the live/USB media is visible, no fixed disk.
    if [ -f "$D/block-lsblk-p.txt" ]; then
        local disks
        disks="$(grep -cE ' disk ' "$D/block-lsblk-p.txt" 2>/dev/null)"
        if [ "${disks:-0}" -le 0 ]; then
            add HIGH "No block devices of type 'disk' present in lsblk" "$(grep -E 'NAME|disk|part|rom' "$D/block-lsblk-p.txt" 2>/dev/null | head -n 8)"
        fi
    fi
}

# 2. Storage controller / driver not bound (NVMe, Dell BOSS, PERC, HBA, iSCSI).
check_storage_driver() {
    local ev
    # NVMe
    ev="$(g "nvme.*(reset|timeout|failed|not ready|Removing after probe failure|controller is down)" $DMESG)"
    [ -n "$ev" ] && add HIGH "NVMe controller/device error during enumeration" "$ev"
    if [ -f "$D/nvme-list.txt" ] && grep -qiE "No NVMe devices|command not found" "$D/nvme-list.txt" 2>/dev/null; then
        if g "nvme" $DMESG >/dev/null; then
            add MEDIUM "Kernel saw NVMe in dmesg but 'nvme list' shows none - driver/namespace not exposed (check Dell BOSS-N1 / NVMe RAID mode in BIOS)" "$(g 'nvme' $DMESG)"
        fi
    fi
    # Dell BOSS (Marvell AHCI) / megaraid / mpt3sas / sas
    ev="$(g "megaraid|mpt3sas|mpt2sas|marvell|88se|boss|sas_|scsi host.*added|ahci.*(abar|fail)" $DMESG)"
    [ -n "$ev" ] && add MEDIUM "RAID/SAS/AHCI controller messages present - verify the right driver bound (Dell BOSS=ahci/marvell, PERC=megaraid_sas, HBA=mpt3sas)" "$ev"
    # iSCSI
    ev="$(g "iscsi.*(login|timeout|failed|no route|connection.*(refused|reset)|cannot make connection)" "$D/iscsi-sessions.txt $D/iscsi-node.txt" $DMESG $J)"
    [ -n "$ev" ] && add HIGH "iSCSI session/login problem - target unreachable or auth failure" "$ev"
    if [ -f "$D/iscsi-sessions.txt" ] && grep -qiE "No active sessions|could not" "$D/iscsi-sessions.txt" 2>/dev/null; then
        add MEDIUM "No active iSCSI sessions - check initiator config, network in initramfs (ip=dhcp), and target reachability" "$(head -n 4 "$D/iscsi-sessions.txt")"
    fi
    # I/O errors on the chosen disk
    ev="$(g "I/O error|critical medium error|unrecovered read error|buffer I/O error" $DMESG)"
    [ -n "$ev" ] && add MEDIUM "Disk I/O errors - failing/unstable media on the target disk" "$ev"
}

# 3. Disk too small (existing check-disk-size.sh path or installer message).
check_disk_size() {
    local ev
    ev="$(g "not enough (free )?disk|no space left|disk.*too small|insufficient.*space|required:.*Free:" $J $D/var-log)"
    [ -n "$ev" ] && add HIGH "Insufficient disk space for install" "$ev"
}

# 4. Immucore / live-image / sysroot mount failure.
check_immucore() {
    local ev
    ev="$(g "immucore.*(error|fail|timeout)|cannot mount.*sysroot|sysrootwait|rd.live.*(fail|not found)|squashfs.*error|overlay.*fail" $J $DMESG)"
    [ -n "$ev" ] && add HIGH "Immucore/live-image assembly failed (sysroot/overlay/squashfs) - often bad media or sysrootwait timeout" "$ev"
}

# 5. Networking / registration endpoint unreachable.
check_network() {
    local ev
    ev="$(g "no carrier|link is not ready|dhcp.*(fail|timeout|no lease)|name or service not known|could not resolve|connection refused|i/o timeout|tls handshake|x509|certificate" $J $NET)"
    [ -n "$ev" ] && add MEDIUM "Network/registration connectivity problem (DHCP, DNS, TLS, or endpoint unreachable)" "$ev"
    if [ -f "$D/net-ip-addr.txt" ] && ! grep -qE "inet [0-9]" "$D/net-ip-addr.txt" 2>/dev/null; then
        add MEDIUM "No IPv4 address on any interface - NIC driver missing or DHCP failed" "$(grep -E 'state|link/ether|NO-CARRIER' "$D/net-ip-addr.txt" 2>/dev/null | head -n 6)"
    fi
}

# 6. Blank screen / dropped to localhost: install unit never ran or failed.
check_blank_screen() {
    local ev
    ev="$(g "Reached target.*Emergency|emergency.target|rescue.target|Failed to start|Welcome to emergency mode|Cannot open access to console|getty" $J $D/systemd-failed.txt)"
    [ -n "$ev" ] && add MEDIUM "System reached emergency/rescue or a unit failed to start (matches 'blank screen' / drops-to-localhost symptom) - see systemd-failed.txt" "$ev"
    if [ -f "$D/systemd-failed.txt" ] && grep -qiE "kairos|stylus|install|agent" "$D/systemd-failed.txt" 2>/dev/null; then
        add HIGH "An installer/agent systemd unit is in failed state" "$(grep -iE 'kairos|stylus|install|agent|failed' "$D/systemd-failed.txt" | head -n 6)"
    fi
}

# 7. Content bundle / cluster-config extraction failure.
check_content() {
    local ev
    ev="$(g "content.*(fail|error|corrupt)|zstd.*error|tar:.*error|cluster.*config.*(fail|missing)|spc.*(fail|missing)" $J $D/var-log)"
    [ -n "$ev" ] && add MEDIUM "Content-bundle or cluster-config extraction problem" "$ev"
}

# 8. K8s provider / luet install failure.
check_provider() {
    local ev
    ev="$(g "luet.*(error|fail)|provider.*(error|fail)|failed to (pull|install).*(k3s|rke2|kubeadm|nodeadm)|image pull.*fail" $J $D/var-log)"
    [ -n "$ev" ] && add LOW "Kubernetes provider/luet package install error" "$ev"
}

# 9. Generic kernel panic / OOM as a last resort.
check_panic() {
    local ev
    ev="$(g "kernel panic|Out of memory|Killed process|BUG: |general protection fault|Call Trace" $DMESG $J)"
    [ -n "$ev" ] && add MEDIUM "Kernel panic / OOM / crash detected" "$ev"
}

# ----------------------------------------------------------------------------
# Report
# ----------------------------------------------------------------------------
sev_rank() { case "$1" in HIGH) echo 0;; MEDIUM) echo 1;; LOW) echo 2;; *) echo 3;; esac; }

main() {
    echo "==================================================================="
    echo " Palette Edge installer debug bundle - root-cause analysis"
    echo " Source: $INPUT"
    [ -f "$D/MANIFEST.txt" ] && { echo " ---"; sed 's/^/ /' "$D/MANIFEST.txt"; }
    echo "==================================================================="

    check_no_disk
    check_storage_driver
    check_disk_size
    check_immucore
    check_network
    check_blank_screen
    check_content
    check_provider
    check_panic

    if [ ${#FINDINGS[@]} -eq 0 ]; then
        echo
        echo "No known failure signatures matched."
        echo "Inspect manually - start with these files:"
        echo "  journal-errors.txt, systemd-failed.txt, storage-dmesg.txt,"
        echo "  block-lsblk-p.txt, net-ip-addr.txt"
        return 0
    fi

    # Sort findings by severity.
    local sorted=()
    while IFS= read -r line; do sorted+=("$line"); done < <(
        for f in "${FINDINGS[@]}"; do echo "$(sev_rank "${f%%|*}")|$f"; done | sort -t'|' -k1,1n | cut -d'|' -f2-
    )

    echo
    echo "Likely root cause(s), most severe first:"
    echo
    local n=1
    for f in "${sorted[@]}"; do
        local sev="${f%%|*}"; local rest="${f#*|}"
        local title="${rest%%|*}"; local ev="${rest#*|}"
        echo "[$n] ($sev) $title"
        echo "    evidence:"
        printf '%s\n' "${ev//~~NL~~/$'\n'}" | sed 's/^/      | /'
        echo
        n=$((n+1))
    done
    echo "Note: signatures are heuristic. Confirm against the full journal."
}

main
