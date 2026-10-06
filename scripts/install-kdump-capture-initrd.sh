#!/usr/bin/env bash
#
# install-kdump-capture-initrd.sh
#
# Build the kdump capture initrd for the image's kernel, using dracut, and
# assert that it is a usable capture initrd before the build continues.
#
# WHY THIS EXISTS
# ---------------
# kdump needs a SECOND initrd -- the one the crash kernel boots into after a
# panic. The kernel binary is the same one that is already running; only the
# initrd differs. The crash kernel is loaded ahead of time with
#   kexec -p <vmlinuz> --initrd=<capture initrd> --command-line="<cmdline>"
#
# `kdump-tools` generates that initrd with `mkinitramfs` (initramfs-tools). On
# this image the boot initrd is generated with dracut instead, and the root
# filesystem is assembled by dracut-only machinery: the Kairos framework's
# modules for an installed system, and dracut-live for the live ISO. An
# initramfs-tools capture initrd has none of that, so it cannot resolve
# `root=`, the crash kernel fails to mount root, and no vmcore is ever written.
#
# The capture initrd is therefore generated here with dracut, using the same
# command form the boot initrd uses, so both get the same module set and the
# same root-management behaviour. The build fails if they disagree.
#
# Constraints this script works under:
#   - It builds the initrd itself rather than leaving it to the package. The
#     package's generator is a dpkg kernel hook, /etc/kernel/postinst.d/kdump-tools,
#     so it only runs when a kernel is installed -- and both the hook and the
#     kernel arrive before this image's kdump-tools install, with no later kernel
#     install to trigger it. It is also mkinitramfs-only: kdump-tools 1:1.10.3ubuntu2,
#     the version noble ships, contains no dracut support at all. Whichever of the
#     two reasons applies, the package does not produce the initrd this image needs.
#   - dracut is invoked with an explicit kernel version and output path. It
#     never relies on the ordering of /lib/modules.
#   - The package's conffile for `/etc/default/kdump-tools` is replaced by the
#     image's own copy, shipped from the same guarded block that installs the
#     package. Nothing here reads it, but the two must agree on where the capture
#     initrd lives: that file sets KDUMP_INITRD=/usr/lib/kdump/initrd.img, which
#     is the stable symlink this script creates in step 4.
#
# Exit status: non-zero on any failed assertion, so the build stops rather than
# shipping an image with a missing, empty, or non-dracut capture initrd.

set -euo pipefail

KDUMP_DIR="/var/lib/kdump"
UNIT="kdump-tools.service"

# Where the capture initrd and its stable symlinks actually live.
#
# NOT under /var/lib/kdump, which is the directory kdump-tools uses by default.
# On this image /var is a tmpfs-backed overlay (kairos-init 00_rootfs.yaml), so
# the running root does not see what the image placed there -- an explicit
# KDUMP_INITRD pointing into /var would resolve to nothing and kdump-config would
# exit 1 at load. /usr is part of the immutable root and is present in both the
# installed system and the live ISO, which is the property this needs.
KDUMP_SHARE="/usr/lib/kdump"

# --- 1. Resolve the kernel to build for -------------------------------------
# The image ships one kernel, but never depend on readdir order to find it.
mapfile -t _kvers < <(printf '%s\n' /lib/modules/* | xargs -n1 basename | sort -V)
if [ "${#_kvers[@]}" -eq 0 ]; then
    echo "FATAL: no kernel found under /lib/modules -- refusing to build a capture initrd" >&2
    exit 1
fi
KVER="${_kvers[${#_kvers[@]}-1]}"
if [ "${#_kvers[@]}" -gt 1 ]; then
    echo "WARNING: multiple kernels installed (${_kvers[*]}); building a capture initrd for ${KVER} only." >&2
    echo "WARNING: kdump will have no capture initrd for the others." >&2
fi

VMLINUZ="/boot/vmlinuz-${KVER}"
BOOT_INITRD="/boot/initrd-${KVER}"
CAPTURE_INITRD="${KDUMP_SHARE}/initrd.img-${KVER}"
CAPTURE_INITRD_LINK="${KDUMP_SHARE}/initrd.img"
KERNEL_LINK="${KDUMP_SHARE}/vmlinuz"

if [ ! -f "$VMLINUZ" ]; then
    echo "FATAL: ${VMLINUZ} not found -- cannot build a capture initrd for a kernel that is not installed" >&2
    exit 1
fi
if [ ! -s "$BOOT_INITRD" ]; then
    echo "FATAL: ${BOOT_INITRD} is missing or empty -- the boot initrd must exist before the" >&2
    echo "       capture initrd is derived from it. Check the dracut step that precedes this one." >&2
    exit 1
fi

# --- 2. Build ---------------------------------------------------------------
# Reads /etc/dracut.conf.d/*.conf, the same drop-ins the boot initrd is built
# from, so the two images share a module set.
install -d -m 0755 "$KDUMP_SHARE"
install -d -m 0755 "$KDUMP_DIR"
# Create the dump directory up front so the user-space save that runs after the
# crash reboot has somewhere to write even if it does not create it itself.
# Harmless on a live-ISO boot, where /usr/local is the writable RAM overlay.
install -d -m 0755 /usr/local/kdump
echo "Building kdump capture initrd with dracut: ${CAPTURE_INITRD} (kernel ${KVER})"
dracut -f "$CAPTURE_INITRD" "$KVER"

# --- 3. Assert the capture initrd is usable ---------------------------------
if [ ! -s "$CAPTURE_INITRD" ]; then
    echo "FATAL: ${CAPTURE_INITRD} is missing or empty after dracut ran" >&2
    exit 1
fi

# Every check below reads an initrd with lsinitrd, which ships in dracut-core.
# Assert it is present so a missing reader is reported as itself rather than
# looking like two corrupt initrds.
if ! command -v lsinitrd >/dev/null 2>&1; then
    echo "FATAL: lsinitrd is not on PATH, so neither initrd can be inspected." >&2
    echo "       It comes from dracut-core, which this image must have installed." >&2
    exit 1
fi

# lsinitrd is dracut's own reader and works only on dracut-built images. The
# module list is embedded in the image as /lib/dracut/modules.txt, and
# `lsinitrd -f` prints that file verbatim -- so a non-empty read proves the
# image is dracut-built AND yields the list to compare.
#
# Read the embedded file rather than scraping "dracut modules:" out of the
# human-readable listing. That line is a BARE header on this dracut
# (060+5-1ubuntu3.3, the version the noble-based images ship): the module names
# follow on the lines below it, one per line. A
# `sed -n 's/^dracut modules: //p'` therefore matches nothing, reports every
# initrd as having no modules at all, and fails the build on the very boot
# initrd it was meant to check.
#
# /lib is a symlink to /usr/lib on these images, so the file is stored under
# usr/ inside the archive; both spellings are tried because `lsinitrd -f`
# matches the path as stored. A path that is not in the image makes lsinitrd
# exit 0 with no output, so emptiness -- not exit status -- discriminates.
_mods() {
    local initrd="$1" path out
    for path in usr/lib/dracut/modules.txt lib/dracut/modules.txt; do
        out="$(lsinitrd -f "$path" "$initrd" 2>/dev/null || true)"
        if [ -n "$out" ]; then
            printf '%s\n' "$out" | sed '/^$/d' | sort -u
            return 0
        fi
    done
    return 1
}

# `|| true` is load-bearing: under `set -e` a command substitution that fails an
# assignment aborts the script outright, so an unreadable list would end the
# build here instead of reaching the diagnostics below that say why.
_boot_mods="$(_mods "$BOOT_INITRD" || true)"
_cap_mods="$(_mods "$CAPTURE_INITRD" || true)"

if [ -z "$_boot_mods" ]; then
    echo "FATAL: could not read the dracut module list from ${BOOT_INITRD}." >&2
    echo "       Either the boot initrd is not dracut-built, or it has no" >&2
    echo "       /lib/dracut/modules.txt for lsinitrd to read." >&2
    echo "       Both cases break the assumption this script exists to enforce." >&2
    exit 1
fi
if [ -z "$_cap_mods" ]; then
    echo "FATAL: ${CAPTURE_INITRD} is not a dracut initrd (no readable module list)." >&2
    echo "       A capture initrd without the image's root-assembly modules cannot mount root." >&2
    exit 1
fi

_missing="$(comm -23 <(printf '%s\n' "$_boot_mods") <(printf '%s\n' "$_cap_mods"))"
if [ -n "$_missing" ]; then
    echo "FATAL: the capture initrd is missing modules that the boot initrd has:" >&2
    printf '         %s\n' $_missing >&2
    echo "       The crash kernel would boot without the modules that assemble this root." >&2
    exit 1
fi

# Live-boot capability report.
#
# The live ISO boots the same /boot/initrd this script compares against (the
# ISO's grub.cfg loads /boot/initrd, which the base-image dracut step creates
# alongside the kernel), so module parity with the boot initrd is the whole
# check. dmsquash-live is the module that assembles root=live:CDLABEL=..., and
# on this image family the dracut conf files add it explicitly; without it a
# capture kernel cannot reach the live root. Report it rather than assume it.
if ! printf '%s\n' "$_cap_mods" | grep -qx 'dmsquash-live'; then
    echo "WARNING: dmsquash-live is absent from ${CAPTURE_INITRD}." >&2
    echo "         A capture kernel booted from a live ISO (root=live:CDLABEL=...) will not" >&2
    echo "         reach switch_root, so no vmcore is written for live-ISO panics." >&2
    echo "         Installed-system capture (root=LABEL=COS_ACTIVE + cos-img/filename=) does" >&2
    echo "         not need it. Check the dracut conf drop-ins if the live case is required." >&2
fi

# --- 4. Publish under the names kdump-tools and the conffile expect ---------
# The image's /etc/default/kdump-tools points KDUMP_KERNEL and KDUMP_INITRD at
# these two stable, version-free symlinks, so one file serves every kernel and
# nothing has to be re-edited on a kernel bump.
ln -sfn "$(basename "$CAPTURE_INITRD")" "$CAPTURE_INITRD_LINK"
ln -sfn "$VMLINUZ" "$KERNEL_LINK"

# Keep kdump-tools' own directory coherent as well.
#
# kdump-config's kdump_create_symlinks() falls back to its mkinitramfs-based hook
# whenever /var/lib/kdump/initrd.img-<kver> is absent, and that hook would write a
# non-dracut initrd. A hard link (same filesystem during the build) keeps the
# upstream path populated at no extra image size, so that fallback is not taken.
# On a running system this copy may be invisible anyway, since /var is a tmpfs
# overlay -- which is exactly why KDUMP_INITRD does not point here.
ln -f "$CAPTURE_INITRD" "${KDUMP_DIR}/initrd.img-${KVER}" 2>/dev/null || \
    cp -f "$CAPTURE_INITRD" "${KDUMP_DIR}/initrd.img-${KVER}"

# kdump-config's check_sysctl_change() deletes /var/lib/kdump/initrd.img-<kver>
# whenever /etc/kdump/sysctl.conf differs from the copy it last recorded, and it
# runs on every load -- including the first boot, where the recorded copy does not
# exist yet and the comparison therefore fails. Seeding the recorded copy means the
# first load does not treat the packaged sysctls as a change.
if [ -f /etc/kdump/sysctl.conf ]; then
    install -m 0644 /etc/kdump/sysctl.conf "${KDUMP_DIR}/latest_sysctls-${KVER}"
fi

# kdump-tools regenerates the capture initrd when it is missing or older than
# the kernel binary, and its generator is mkinitramfs. Keep this file newer than
# both the kernel and the boot initrd so that path is never taken on the device.
touch "$CAPTURE_INITRD"
if [ "$CAPTURE_INITRD" -ot "$VMLINUZ" ]; then
    echo "FATAL: ${CAPTURE_INITRD} is older than ${VMLINUZ}; kdump-tools would regenerate it with" >&2
    echo "       mkinitramfs and silently discard the dracut-built image." >&2
    exit 1
fi

# --- 5. Assert kdump will actually start on the device ---------------------
# A unit that is installed but never enabled produces a clean-looking image and
# no dump. Assert the wants-link rather than trusting the package postinst,
# which runs without a systemd instance during the image build.
if [ ! -f "/lib/systemd/system/${UNIT}" ] && [ ! -f "/usr/lib/systemd/system/${UNIT}" ]; then
    echo "FATAL: ${UNIT} is not present -- the kdump-tools package did not install its unit" >&2
    exit 1
fi

UNIT_PATH="/usr/lib/systemd/system/${UNIT}"
[ -f "$UNIT_PATH" ] || UNIT_PATH="/lib/systemd/system/${UNIT}"
WANTED_BY="$(sed -n 's/^WantedBy=//p' "$UNIT_PATH" | tr ' ' '\n' | sed '/^$/d' | head -n1)"
if [ -z "$WANTED_BY" ]; then
    echo "FATAL: ${UNIT} declares no WantedBy= target, so nothing would ever start it" >&2
    exit 1
fi

WANTS_DIR="/etc/systemd/system/${WANTED_BY}.wants"
install -d -m 0755 "$WANTS_DIR"
ln -sf "$UNIT_PATH" "${WANTS_DIR}/${UNIT}"
if [ ! -e "${WANTS_DIR}/${UNIT}" ]; then
    echo "FATAL: failed to enable ${UNIT} in ${WANTS_DIR}" >&2
    exit 1
fi

# --- 6. Summary -------------------------------------------------------------
echo "kdump capture initrd ready:"
echo "  kernel          : ${KVER}"
echo "  kernel image    : ${VMLINUZ}"
echo "  boot initrd     : ${BOOT_INITRD}"
echo "  capture initrd  : ${CAPTURE_INITRD} ($(stat -c '%s' "$CAPTURE_INITRD") bytes)"
echo "  stable symlinks : ${KERNEL_LINK} -> ${VMLINUZ}"
echo "                    ${CAPTURE_INITRD_LINK} -> $(basename "$CAPTURE_INITRD")"
echo "  boot modules    : $(printf '%s\n' "$_boot_mods" | tr '\n' ' ')"
echo "  capture modules : $(printf '%s\n' "$_cap_mods" | tr '\n' ' ')"
echo "  enabled via     : ${WANTS_DIR}/${UNIT}"
