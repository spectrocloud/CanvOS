#!/bin/bash
#
# collect-debug-bundle.sh
#
# Unattended installer-debug log collector for Palette Edge (CanvOS) installer ISOs.
#
# Purpose
#   When an install fails at a customer site, the operator boots the
#   "Palette Debug Install" GRUB entry (which sets the verbose debug cmdline
#   flags and the marker "palette.debug=1"). This script is then invoked
#   automatically by systemd (emergency/rescue drop-ins, the watchdog timer,
#   or an OnFailure hook) - the operator never has to type anything.
#
#   It snapshots everything useful for root-causing the install failure into a
#   compressed bundle, writes that bundle to a writable removable disk/CD when
#   one is present, and ALWAYS prints a summary (and, when no media is found,
#   the bundle itself as base64) to the console so it can be captured over a
#   serial console or screen recording.
#
# Safety
#   - Best-effort: never aborts the boot. Individual collection steps may fail.
#   - Read-only with respect to the system being installed; only writes to a
#     dedicated bundle directory on detected removable media (or /tmp).
#   - Redacts secrets (tokens, pairing keys, private keys) from configs.
#   - Gated on the "palette.debug" kernel cmdline marker as defence in depth.
#
# Exit status is always 0 so it can be chained from ExecStartPre=- safely.

PROG="collect-debug-bundle"

# ----------------------------------------------------------------------------
# Guard: only run on a debug boot. Defence in depth - the systemd units are
# already gated on ConditionKernelCommandLine=palette.debug.
# ----------------------------------------------------------------------------
if ! grep -qw "palette.debug" /proc/cmdline 2>/dev/null; then
    # Allow forcing for manual/QA runs.
    if [ "${1:-}" != "--force" ]; then
        echo "${PROG}: 'palette.debug' not on kernel cmdline; skipping (use --force to override)."
        exit 0
    fi
fi

# ----------------------------------------------------------------------------
# Single-flight lock: multiple triggers (emergency + watchdog + OnFailure) may
# fire close together. Only the first collects; later ones no-op.
# ----------------------------------------------------------------------------
LOCK=/run/palette-debug.collecting
DONE=/run/palette-debug.collected
if [ -e "$DONE" ] && [ "${1:-}" != "--force" ]; then
    echo "${PROG}: a bundle was already collected this boot ($(cat "$DONE" 2>/dev/null))."
    exit 0
fi
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "${PROG}: another collection is in progress; skipping."
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# ----------------------------------------------------------------------------
# Console helper - write to the real console(s) so serial capture sees it even
# when invoked as a systemd unit.
# ----------------------------------------------------------------------------
log() {
    echo "[$PROG] $*"
    if [ -w /dev/console ]; then
        echo "[$PROG] $*" > /dev/console 2>/dev/null || true
    fi
}

HOST="$(hostname 2>/dev/null || echo unknown)"
# new Date()/timestamps: use the kernel/uptime-independent wall clock if set,
# else fall back to monotonic seconds so the bundle name is still unique.
TS="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%s 2>/dev/null || echo unknown)"
BUNDLE_NAME="palette-debug-${HOST}-${TS}"
WORK="$(mktemp -d /tmp/${BUNDLE_NAME}.XXXXXX 2>/dev/null || echo /tmp/${BUNDLE_NAME})"
mkdir -p "$WORK"

log "==================================================================="
log "Palette Edge installer debug collection starting."
log "Bundle id: ${BUNDLE_NAME}"
log "==================================================================="

# run <outfile> <command...> : best-effort capture of a command's output.
run() {
    local out="$WORK/$1"; shift
    {
        echo "### \$ $*"
        if command -v "${1}" >/dev/null 2>&1 || [ "${1#/}" != "$1" ]; then
            timeout 60 "$@" 2>&1
        else
            echo "(command '${1}' not available)"
        fi
        echo
    } >> "$out" 2>&1
}

# copyf <src> <destname> : best-effort copy of a file/dir if it exists.
copyf() {
    local src="$1" dst="$WORK/$2"
    if [ -e "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp -aL "$src" "$dst" 2>/dev/null || cp -a "$src" "$dst" 2>/dev/null || true
    fi
}

# ----------------------------------------------------------------------------
# 1. Boot / kernel / cmdline
# ----------------------------------------------------------------------------
log "Collecting boot & kernel state..."
copyf /proc/cmdline   cmdline.txt
run   uname.txt        uname -a
run   dmesg.txt        dmesg -T
run   loaded-modules.txt lsmod

# ----------------------------------------------------------------------------
# 2. systemd / journal (the heart of post-pivot failures, e.g. blank screen,
#    drops to localhost, install service failure)
# ----------------------------------------------------------------------------
log "Collecting journal & systemd state..."
run journal-full.txt        journalctl --no-pager -b
run journal-errors.txt      journalctl --no-pager -b -p err
run systemd-failed.txt      systemctl --no-pager --failed
run systemd-list-units.txt  systemctl --no-pager list-units
run systemd-list-jobs.txt   systemctl --no-pager list-jobs
# Anything that mentions the installer/agent/immucore/stylus by name.
run kairos-stylus.txt       bash -c "journalctl --no-pager -b | grep -iE 'kairos|stylus|immucore|cos-setup|install|elemental' || true"

# ----------------------------------------------------------------------------
# 3. Storage / disk enumeration (iSCSI, NVMe, Dell BOSS, PERC, HBA ...)
#    This is the high-value section for "install disk not found". We also
#    actively probe so the evidence exists even if rd.driver.pre missed it.
# ----------------------------------------------------------------------------
log "Collecting storage & disk-enumeration state..."
run block-lsblk.txt     lsblk -O
run block-lsblk-p.txt   lsblk -p -o NAME,TYPE,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT,MODEL,SERIAL,TRAN,ROTA
run block-blkid.txt     blkid
run block-byid.txt      ls -l /dev/disk/by-id
run block-bypath.txt    ls -l /dev/disk/by-path
run block-bylabel.txt   ls -l /dev/disk/by-label
run pci-devices.txt     lspci -nnk
run scsi-devices.txt    bash -c "ls -l /sys/class/scsi_disk /sys/class/scsi_host 2>/dev/null; cat /proc/scsi/scsi 2>/dev/null"
run nvme-list.txt       nvme list
run iscsi-sessions.txt  iscsiadm -m session -P 3
run iscsi-node.txt      iscsiadm -m node
run multipath.txt       multipath -ll
run mounts.txt          mount
run df.txt              df -h
run dmsetup.txt         dmsetup ls --tree

# Driver/enumeration messages from the kernel ring buffer.
run storage-dmesg.txt   bash -c "dmesg -T | grep -iE 'nvme|ahci|megaraid|mpt|sas|scsi|iscsi|ata[0-9]|boss|marvell|usb-storage|sd [a-z]|EXT4|XFS|I/O error|failed' || true"

# ----------------------------------------------------------------------------
# 4. Networking (registration / endpoint-unreachable failures)
# ----------------------------------------------------------------------------
log "Collecting network state..."
run net-ip-addr.txt     ip -d addr
run net-ip-route.txt    ip route
run net-ip-link.txt     ip -s link
run net-resolv.txt      cat /etc/resolv.conf
run net-dns.txt         bash -c "journalctl --no-pager -b -u systemd-resolved 2>/dev/null || true"

# ----------------------------------------------------------------------------
# 5. Hardware inventory
# ----------------------------------------------------------------------------
log "Collecting hardware inventory..."
run dmidecode.txt       dmidecode
run cpuinfo.txt         cat /proc/cpuinfo
run meminfo.txt         cat /proc/meminfo

# ----------------------------------------------------------------------------
# 6. Kairos / Stylus / Palette install artifacts & logs (with redaction)
# ----------------------------------------------------------------------------
log "Collecting Kairos/Stylus install artifacts (secrets redacted)..."
copyf /var/log                         var-log
copyf /usr/local/installer.log         installer.log
copyf /run/cos                         run-cos
copyf /run/immucore                    run-immucore
copyf /oem                             oem
copyf /etc/kairos                      etc-kairos
copyf /etc/elemental                   etc-elemental
copyf /opt/spectrocloud/state          spectrocloud-state

# Cloud-config / user-data: copy then redact obvious secrets in place.
for cfg in /oem/*.yaml /etc/elemental/config.yaml /run/initramfs/live/config.yaml \
           /run/initramfs/live/.edge_custom_config.yaml /tmp/user-data; do
    [ -e "$cfg" ] && copyf "$cfg" "configs$(echo "$cfg" | tr '/' '_')"
done
# Redact tokens / keys / passwords from everything we collected.
if command -v find >/dev/null 2>&1; then
    find "$WORK" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.conf' -o -name 'config*' \) 2>/dev/null \
    | while read -r f; do
        sed -i -E 's/(([Tt]oken|[Pp]assword|[Pp]asswd|[Ss]ecret|pairing[-_]?key|[Aa]pi[-_]?[Kk]ey|[Pp]rivate[-_]?[Kk]ey)["'"'"']?[[:space:]]*[:=][[:space:]]*).*/\1<REDACTED>/g' "$f" 2>/dev/null || true
    done
fi

# ----------------------------------------------------------------------------
# 7. Manifest
# ----------------------------------------------------------------------------
{
    echo "bundle:        ${BUNDLE_NAME}"
    echo "host:          ${HOST}"
    echo "collected_utc: ${TS}"
    echo "cmdline:       $(cat /proc/cmdline 2>/dev/null)"
    echo "trigger:       ${1:-unspecified}"
    echo "collector:     ${PROG} (CanvOS installer debug menu)"
} > "$WORK/MANIFEST.txt"

# ----------------------------------------------------------------------------
# 8. Compress
# ----------------------------------------------------------------------------
log "Compressing bundle..."
TARBALL="/tmp/${BUNDLE_NAME}.tar.gz"
if tar -czf "$TARBALL" -C "$(dirname "$WORK")" "$(basename "$WORK")" 2>/dev/null; then
    SHA="$(sha256sum "$TARBALL" 2>/dev/null | awk '{print $1}')"
    SIZE="$(du -h "$TARBALL" 2>/dev/null | awk '{print $1}')"
    log "Bundle created: ${TARBALL} (${SIZE}, sha256=${SHA})"
else
    log "ERROR: failed to create tarball; leaving raw files under ${WORK}"
    TARBALL=""
fi

# ----------------------------------------------------------------------------
# 9. Try to persist the bundle to writable removable media (USB / CD-RW / any
#    writable, non-live filesystem). The install target disk is deliberately
#    NOT used - it may be the failure cause, and is usually being wiped.
# ----------------------------------------------------------------------------
SAVED_PATH=""
save_to_media() {
    [ -n "$TARBALL" ] || return 1
    local dest_dir="$1"
    mkdir -p "$dest_dir/palette-debug" 2>/dev/null || return 1
    if cp "$TARBALL" "$dest_dir/palette-debug/" 2>/dev/null; then
        sync 2>/dev/null || true
        SAVED_PATH="$dest_dir/palette-debug/$(basename "$TARBALL")"
        return 0
    fi
    return 1
}

if [ -n "$TARBALL" ]; then
    log "Looking for writable removable media to save the bundle..."

    # (a) Already-mounted, writable, non-pseudo, non-live filesystems.
    while read -r src mnt fstype opts _; do
        case "$fstype" in tmpfs|squashfs|overlay|devtmpfs|proc|sysfs|iso9660|""|none) continue;; esac
        case "$mnt"   in /|/run*|/proc*|/sys*|/dev*|/tmp|/oem|/usr/local|/run/initramfs/*) continue;; esac
        case "$opts"  in ro,*|*,ro|*,ro,*) continue;; esac
        if save_to_media "$mnt"; then break; fi
    done < <(cat /proc/mounts 2>/dev/null)

    # (b) Nothing mounted writable: try to mount removable block partitions.
    if [ -z "$SAVED_PATH" ]; then
        for dev in $(lsblk -prno NAME,RM,TYPE 2>/dev/null | awk '$2==1 && $3=="part"{print $1}'); do
            mp="/run/palette-debug-mnt"
            mkdir -p "$mp" 2>/dev/null || continue
            if mount "$dev" "$mp" 2>/dev/null; then
                if save_to_media "$mp"; then umount "$mp" 2>/dev/null; break; fi
                umount "$mp" 2>/dev/null
            fi
        done
    fi
fi

# ----------------------------------------------------------------------------
# 10. Report on console (ALWAYS). If no media, stream base64 for serial capture.
# ----------------------------------------------------------------------------
log "==================================================================="
if [ -n "$SAVED_PATH" ]; then
    log "SUCCESS: debug bundle saved to removable media:"
    log "    FILE:   $SAVED_PATH"
    log "    SHA256: ${SHA}"
    log "Remove the media and attach this file to your support ticket."
    echo "${SAVED_PATH}" > "$DONE" 2>/dev/null || true
elif [ -n "$TARBALL" ]; then
    log "No writable removable media found."
    log "The bundle could not be saved to disk; it is printed below as base64."
    log "Capture ALL of the following lines from your serial/screen recording,"
    log "then decode with:  base64 -d > ${BUNDLE_NAME}.tar.gz"
    log "----------8<------- BEGIN ${BUNDLE_NAME}.tar.gz (base64) -------8<----------"
    base64 "$TARBALL" 2>/dev/null | tee /dev/console 2>/dev/null
    log "----------8<------- END ${BUNDLE_NAME}.tar.gz (base64) -------8<----------"
    echo "console-base64" > "$DONE" 2>/dev/null || true
else
    log "ERROR: no bundle produced. Raw logs are under ${WORK} (lost on reboot)."
fi
log "Palette Edge installer debug collection finished."
log "==================================================================="

exit 0
