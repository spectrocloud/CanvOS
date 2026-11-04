#!/usr/bin/env bash
#
# build-kdump.sh -- image-build step for kdump on Ubuntu (PE-9067).
#
# Checks that the image defaults are in the image and that makedumpfile supports the image kernel,
# builds the capture initrd, enables kdump-tools.service, removes the package's /etc/default/kdump-tools
# (kdump-merge builds it before every start), and fails the image build if the result could not
# produce a dump. Runs after
# kdump-tools, makedumpfile and the files under overlay/kdump/ubuntu/ are installed.
#
# kdump-tools only builds initrds with mkinitramfs, which cannot assemble a Kairos root.
# The dump is written after switch_root, so the capture initrd is built with dracut from
# the same root-assembly modules (immucore) as the boot initrd.
set -euo pipefail

KDUMP_SHARE=/usr/lib/kdump
KDUMP_DIR=/var/lib/kdump
DEFAULTS=/etc/default/kdump-tools.default
CONF=/etc/default/kdump-tools
MAKEDUMPFILE_LIMIT="${KDUMP_SHARE}/makedumpfile-supported-kernel"
UNIT=kdump-tools.service
UNIT_DIR=/usr/lib/systemd/system
ETC_UNIT_DIR=/etc/systemd/system

# Not needed to assemble a local root. The network group goes together: only url-lib,
# livenet, iscsi, nbd and nfs depend on it.
KDUMP_OMIT_MODULES="${KDUMP_OMIT_MODULES:-resume systemd-sysext systemd-networkd systemd-resolved network network-legacy url-lib kernel-network-modules livenet qemu-net iscsi nbd nfs}"
# Must stay, with their dependencies: boot basics plus what assembles the Kairos root.
KDUMP_REQUIRED_MODULES="base systemd systemd-initrd dracut-systemd udev-rules kernel-modules immucore rootfs-block dm fs-lib lvm overlayfs overlay-root crypt"

fatal() { printf 'FATAL: %s\n' "$@" >&2; exit 1; }
warn()  { printf 'WARNING: %s\n' "$@" >&2; }

# The image defaults must be in the image: kdump-merge builds /etc/default/kdump-tools from them at
# every start. Checked first, before the capture initrd is built.
check_defaults() {
    local want bad
    [ -s "$DEFAULTS" ] || fatal "${DEFAULTS} is missing or empty; it must be copied into the image"
    for want in 'USE_KDUMP=1' "KDUMP_KERNEL=${KDUMP_SHARE}/vmlinuz" "KDUMP_INITRD=${KDUMP_SHARE}/initrd.img" \
                'KDUMP_COREDIR=/usr/local/kdump' 'MAKEDUMP_ARGS="-F -c -d 31"'; do
        grep -qxF "$want" "$DEFAULTS" || fatal "${DEFAULTS} lacks ${want}"
    done
    grep -q '^KDUMP_CMDLINE_APPEND=.*kho=off' "$DEFAULTS" || fatal "${DEFAULTS} capture arguments lack kho=off"
    bad="$(grep -vE '^(#.*|[A-Z_][A-Z0-9_]*=.*|)$' "$DEFAULTS" | tr '\n' ' ' || true)"
    [ -z "${bad// /}" ] || fatal "${DEFAULTS} has lines that are not KEY=value: ${bad}"
}

# Sets KVER, VMLINUZ, BOOT_INITRD, CAPTURE_INITRD for the image's kernel.
resolve_kernel() {
    local kvers
    mapfile -t kvers < <(find /lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort -V)
    [ "${#kvers[@]}" -gt 0 ] || fatal "no kernel under /lib/modules"
    KVER="${kvers[${#kvers[@]}-1]}"
    [ "${#kvers[@]}" -eq 1 ] || warn "several kernels (${kvers[*]}); capture initrd for ${KVER} only"

    VMLINUZ="/boot/vmlinuz-${KVER}"
    BOOT_INITRD="/boot/initrd-${KVER}"
    CAPTURE_INITRD="${KDUMP_SHARE}/initrd.img-${KVER}"
    [ -f "$VMLINUZ" ] || fatal "${VMLINUZ} not found"
    [ -s "$BOOT_INITRD" ] || fatal "${BOOT_INITRD} is missing; the boot initrd must be built first"
}

# makedumpfile must support the image kernel: past its LATEST_VERSION it only warns, and its page
# filtering can be wrong. +makedumpfile-match records that version next to the package.
check_makedumpfile() {
    local latest
    command -v makedumpfile >/dev/null 2>&1 || fatal "makedumpfile is not installed"
    latest="$(cat "$MAKEDUMPFILE_LIMIT" 2>/dev/null || true)"
    [ -n "$latest" ] || fatal "${MAKEDUMPFILE_LIMIT} is missing or empty"
    dpkg --compare-versions "${KVER%%-*}" le "$latest" \
        || fatal "kernel ${KVER} is newer than makedumpfile supports (${latest}); bump +makedumpfile-match"
}

# Generic, like the boot initrd (hostonly="no" from dracut.conf.d): the build host's
# hardware says nothing about the appliance's. Microcode survives the kexec.
build_initrd() {
    install -d -m 0755 "$KDUMP_SHARE" "$KDUMP_DIR"
    dracut -f --no-early-microcode --omit "$KDUMP_OMIT_MODULES" "$CAPTURE_INITRD" "$KVER"
    [ -s "$CAPTURE_INITRD" ] || fatal "${CAPTURE_INITRD} is missing after dracut"
}

# initrd_modules <initrd>: the module list dracut embeds; fails if there is none.
initrd_modules() {
    local path out
    for path in usr/lib/dracut/modules.txt lib/dracut/modules.txt; do
        out="$(lsinitrd -f "$path" "$1" 2>/dev/null || true)"
        [ -n "$out" ] && { printf '%s\n' "$out" | sed '/^$/d' | sort -u; return 0; }
    done
    return 1
}

# module_depends <module>: direct dependencies from the module's depends().
module_depends() {
    local d
    for d in /usr/lib/dracut/modules.d/[0-9][0-9]"$1"; do [ -d "$d" ] && break; done
    [ -d "$d" ] || return 0
    ( set +eu +o pipefail
      # shellcheck source=/dev/null
      . /usr/lib/dracut/dracut-functions.sh >/dev/null 2>&1
      # shellcheck source=/dev/null
      . "$d/module-setup.sh" >/dev/null 2>&1
      declare -F depends >/dev/null 2>&1 && depends 2>/dev/null ) | tr ' ' '\n' | sed '/^$/d' || true
}

# module_closure <modules...>: the modules plus all their dependencies.
module_closure() {
    local seen=" " todo="$*" next m
    while :; do
        next=""
        for m in $todo; do
            case "$seen" in *" $m "*) continue ;; esac
            seen="${seen}${m} "
            next="$next $(module_depends "$m" | tr '\n' ' ')"
        done
        [ -n "${next// /}" ] || break
        todo="$next"
    done
    # shellcheck disable=SC2086  # one module per word
    printf '%s\n' $seen | sed '/^$/d' | sort -u
}

# Every boot-initrd module must be in the capture initrd, except the omitted ones and their
# dependencies; anything the required set (with dependencies) needs is never treated as omitted.
check_initrd_modules() {
    local boot cap protected allowed expected missing m
    command -v lsinitrd >/dev/null 2>&1 || fatal "lsinitrd (dracut-core) is not installed"
    boot="$(initrd_modules "$BOOT_INITRD" || true)"
    cap="$(initrd_modules "$CAPTURE_INITRD" || true)"
    [ -n "$boot" ] || fatal "cannot read the dracut module list of ${BOOT_INITRD}"
    [ -n "$cap" ] || fatal "cannot read the dracut module list of ${CAPTURE_INITRD}"

    # shellcheck disable=SC2086  # module lists are word lists
    protected="$(module_closure $KDUMP_REQUIRED_MODULES)"
    # shellcheck disable=SC2086
    allowed="$(comm -23 <(module_closure $KDUMP_OMIT_MODULES) <(printf '%s\n' "$protected"))"
    expected="$(comm -23 <(printf '%s\n' "$boot") <(printf '%s\n' "$allowed"))"
    missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$cap") | tr '\n' ' ')"
    [ -z "${missing// /}" ] || fatal "capture initrd lacks modules that were not omitted: ${missing}"

    for m in $KDUMP_OMIT_MODULES; do
        grep -qx "$m" <<<"$boot" || warn "omitted module ${m} is not in the boot initrd"
    done
    grep -qE '[[:space:]](usr/)?bin/sh( ->|$)' <<<"$(lsinitrd "$CAPTURE_INITRD" 2>/dev/null)" \
        || fatal "${CAPTURE_INITRD} has no /bin/sh"
}

# Version-free names used by KDUMP_KERNEL and KDUMP_INITRD. kdump-config's working
# directory is pre-filled so its mkinitramfs hook never runs: it rebuilds
# initrd.img-<kver> when the file is missing or the saved sysctl copy differs.
publish() {
    ln -sfn "$(basename "$CAPTURE_INITRD")" "${KDUMP_SHARE}/initrd.img"
    ln -sfn "$VMLINUZ" "${KDUMP_SHARE}/vmlinuz"
    ln -f "$CAPTURE_INITRD" "${KDUMP_DIR}/initrd.img-${KVER}" 2>/dev/null \
        || cp -f "$CAPTURE_INITRD" "${KDUMP_DIR}/initrd.img-${KVER}"
    [ ! -f /etc/kdump/sysctl.conf ] || install -m 0644 /etc/kdump/sysctl.conf "${KDUMP_DIR}/latest_sysctls-${KVER}"
}

# Enabled from /usr/lib, not /etc: /etc/systemd is a persistent bind mount on Kairos that keeps the
# first copy of each file, so a link there could never change or go away with a later image
# (hadron/Dockerfile.modules does the same). The package postinst's /etc link is removed so the
# image has one owner. Sets WANTS for check_config.
enable_unit() {
    local unit="${UNIT_DIR}/${UNIT}"
    [ -f "$unit" ] || fatal "${UNIT} is not installed"
    WANTS="$(awk '/^WantedBy=/ { sub(/^WantedBy=/, ""); print $1; exit }' "$unit")"
    [ -n "$WANTS" ] || fatal "${UNIT} has no WantedBy="
    install -d -m 0755 "${UNIT_DIR}/${WANTS}.wants"
    ln -sfn "../${UNIT}" "${UNIT_DIR}/${WANTS}.wants/${UNIT}"
    rm -f "${ETC_UNIT_DIR}/${WANTS}.wants/${UNIT}"
    rmdir "${ETC_UNIT_DIR}/${WANTS}.wants" 2>/dev/null || true
}

# kdump-merge builds /etc/default/kdump-tools from the defaults and the operator overrides before each
# kdump-tools unit starts. The package postinst writes Ubuntu's stock file there; the image ships none.
drop_conf() {
    rm -f "$CONF"
}

check_config() {
    local want u
    [ "$(readlink -f "${UNIT_DIR}/${WANTS}.wants/${UNIT}")" = "${UNIT_DIR}/${UNIT}" ] \
        || fatal "${UNIT} is not enabled under ${UNIT_DIR}/${WANTS}.wants"
    [ ! -e "${ETC_UNIT_DIR}/${WANTS}.wants/${UNIT}" ] || fatal "${UNIT} is still enabled under ${ETC_UNIT_DIR}"
    [ -x "${KDUMP_SHARE}/kdump-merge" ] || fatal "${KDUMP_SHARE}/kdump-merge is missing"
    grep -qx 'ExecCondition=/usr/lib/kdump/kdump-merge --reserved' "${UNIT_DIR}/${UNIT}.d/kdump.conf" 2>/dev/null \
        || fatal "${UNIT} drop-in lacks the reservation check"
    # The units' own EnvironmentFile= is mandatory; the drop-ins reset it to an optional one, because
    # the file only exists once kdump-merge has run.
    for u in "$UNIT" kdump-tools-dump.service; do
        for want in 'EnvironmentFile=' 'EnvironmentFile=-/etc/default/kdump-tools' 'ExecStartPre=-/usr/lib/kdump/kdump-merge'; do
            grep -qxF "$want" "${UNIT_DIR}/${u}.d/kdump.conf" 2>/dev/null || fatal "${u} drop-in lacks ${want}"
        done
    done

    [ ! -e "$CONF" ] || fatal "${CONF} must not be in the image; kdump-merge builds it"
}

main() {
    check_defaults
    resolve_kernel
    check_makedumpfile
    build_initrd
    check_initrd_modules
    publish
    enable_unit
    drop_conf
    check_config
    echo "kdump: capture initrd ${CAPTURE_INITRD} ($(stat -c %s "$CAPTURE_INITRD") bytes) for kernel ${KVER}"
}

main "$@"
