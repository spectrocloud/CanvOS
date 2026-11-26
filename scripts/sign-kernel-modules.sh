#!/usr/bin/env bash
#
# sign-kernel-modules.sh -- sign and verify out-of-tree kernel modules (GPU drivers)
# for Secure Boot, using the MOK key pair.
#
#   sign-kernel-modules.sh sign        <kver> <dir|module>...   sign every module found, then verify
#   sign-kernel-modules.sh verify      <dir|module>...          fail unless every module carries a
#                                                               signature that verifies against the cert
#   sign-kernel-modules.sh fingerprint                          print SHA-256 of the signing cert (DER)
#   sign-kernel-modules.sh signer                               print the CN the kernel reports as "signer"
#   sign-kernel-modules.sh export-cert <file>                   write the public signing cert (DER) to <file>
#   sign-kernel-modules.sh check-key                            fail unless a usable key + cert pair is present
#
# Handles .ko, .ko.zst, .ko.xz and .ko.gz. Any signature already on a module (for example the
# throw-away key DKMS generates inside a container) is stripped and replaced: such a signature
# chains to nothing the firmware trusts, so it is as good as unsigned.
#
# KEY MATERIAL (never written to the image; temp files live on tmpfs and are removed on exit)
#   MOK_PRIV / MOK_DER                      key and certificate CONTENT, the way Vault hands them to the
#                                           pipeline. PEM text, or base64 of the PEM/DER, is accepted.
#   GPU_MODULE_SIGN_KEY_FILE / ..._CERT_FILE  paths, if you have files instead (take precedence).
#   GPU_MODULE_SIGN_CERT_SHA256             expected SHA-256 of the cert (DER). When set, verify refuses
#                                           any other signing certificate. `sign` refuses it too.
#   GPU_MODULE_EXPECTED_SIGNER              override the expected "signer" CN for the signer subcommand.
#   SIGN_FILE                               path to the kernel's scripts/sign-file. Default: looked up in
#                                           the kernel headers for <kver>. If none is found, an
#                                           openssl implementation writing the same layout is used.
#
# `verify` needs only the certificate (public), so it can run where no key is available, for
# example when consuming a pre-built artifact.
#
# LOGGING (nothing printed here ever contains key material: only certificate facts, names,
# sizes and hashes of public data)
#   Every run says which certificate and key are in use, which signing method ran, what each
#   module's signature was before and after, and ends with ONE line that is easy to grep for:
#       GPU MODULE SIGNING: SUCCESS (...)     or     GPU MODULE SIGNING: FAILED (...)
#   GPU_MODULE_SIGNING_DEBUG=1 adds trailer sizes and per-module SHA-256.
#   GPU_MODULE_SIGN_STATUS_FILE=<path> writes a small key=value record of a successful `sign`
#   (status, signer, cert SHA-256, module count, method, time) so it can be read on the node.

set -euo pipefail

MAGIC='~Module signature appended~'
SIGLEN_BYTES=4

MODE=""        # sign | verify, set by the subcommand; makes die() print the FAILED summary line
die() {
    echo "[sign-kernel-modules] ERROR: $*" >&2
    case "${MODE}" in
        sign|verify) echo "[sign-kernel-modules] GPU MODULE SIGNING: FAILED (${MODE}): $*" >&2 ;;
    esac
    exit 1
}
log() { echo "[sign-kernel-modules] $*" >&2; }
dbg() { [ "${GPU_MODULE_SIGNING_DEBUG:-0}" != "1" ] || echo "[sign-kernel-modules] debug: $*" >&2; }

WORK=""     # key material and certificates: tmpfs when available, always removed
BIG=""      # large temporary module copies: a normal directory (see mk_workdir)
cleanup() {
    [ -z "${BIG}" ] || rm -rf "${BIG}"
    if [ -n "${WORK}" ] && [ -d "${WORK}" ]; then
        find "${WORK}" -type f -exec sh -c 'command -v shred >/dev/null 2>&1 && shred -u "$1" 2>/dev/null || rm -f "$1"' _ {} \; 2>/dev/null || true
        rm -rf "${WORK}"
    fi
}
trap cleanup EXIT

command -v openssl >/dev/null 2>&1 || die "openssl is required."

mk_workdir() {
    [ -n "${WORK}" ] && return 0
    umask 077
    if [ -d /dev/shm ] && [ -w /dev/shm ]; then
        WORK="$(mktemp -d /dev/shm/modsign.XXXXXX)"
    else
        WORK="$(mktemp -d "${TMPDIR:-/tmp}/modsign.XXXXXX")"
    fi
    # Module copies must NOT live in /dev/shm: inside a BuildKit RUN that is a ~64 MB tmpfs,
    # and amdgpu.ko alone is ~40 MB unpacked (two copies are held while verifying), which ran
    # it out of space ("No space left on device" -> a bogus MALFORMED signature). They hold no
    # secrets, so a plain temp directory (removed on exit) is fine.
    BIG="$(mktemp -d "${GPU_MODULE_SIGN_TMPDIR:-${TMPDIR:-/tmp}}/modsign-mods.XXXXXX")"
    dbg "key material in ${WORK}; module temp files in ${BIG}"
}

# ---------------------------------------------------------------------------
# Key material
# ---------------------------------------------------------------------------
is_pem() { grep -q -- '-----BEGIN' "$1" 2>/dev/null; }

# $1 = content (string), $2 = out file. Writes PEM text or decoded base64.
content_to_file() {
    local content="$1" out="$2"
    if printf '%s' "${content}" | grep -q -- '-----BEGIN'; then
        printf '%s\n' "${content}" > "${out}"
    else
        printf '%s' "${content}" | tr -d ' \n\r' | base64 -d > "${out}" 2>/dev/null \
            || die "could not base64-decode the supplied key material."
    fi
}

CERT_CN=""    # name the kernel / modinfo report as the signer (the certificate's issuer CN)
CERT_DER=""   # DER certificate
CERT_PEM=""
KEY_PEM=""    # PEM private key (only when signing)

load_cert() {
    [ -n "${CERT_DER}" ] && return 0
    mk_workdir
    local raw="${WORK}/cert.raw"
    if [ -n "${GPU_MODULE_SIGN_CERT_FILE:-}" ]; then
        [ -s "${GPU_MODULE_SIGN_CERT_FILE}" ] || die "GPU_MODULE_SIGN_CERT_FILE='${GPU_MODULE_SIGN_CERT_FILE}' is missing or empty."
        cp "${GPU_MODULE_SIGN_CERT_FILE}" "${raw}"
    elif [ -n "${MOK_DER:-}" ]; then
        content_to_file "${MOK_DER}" "${raw}"
    else
        die "no signing certificate: set MOK_DER (content) or GPU_MODULE_SIGN_CERT_FILE (path)."
    fi
    if is_pem "${raw}"; then
        openssl x509 -in "${raw}" -outform DER -out "${WORK}/cert.der" 2>/dev/null || die "cannot parse the PEM certificate."
    else
        openssl x509 -inform DER -in "${raw}" -outform DER -out "${WORK}/cert.der" 2>/dev/null || die "cannot parse the certificate (not PEM, not DER)."
    fi
    rm -f "${raw}"
    CERT_DER="${WORK}/cert.der"
    CERT_PEM="${WORK}/cert.pem"
    openssl x509 -inform DER -in "${CERT_DER}" -out "${CERT_PEM}"
    local fp; fp="$(cert_fp)"
    if [ -n "${GPU_MODULE_SIGN_CERT_SHA256:-}" ] && [ "${GPU_MODULE_SIGN_CERT_SHA256}" != "${fp}" ]; then
        die "signing certificate SHA-256 ${fp} does not match the pinned GPU_MODULE_SIGN_CERT_SHA256=${GPU_MODULE_SIGN_CERT_SHA256}."
    fi
    openssl x509 -inform DER -in "${CERT_DER}" -noout -checkend 0 >/dev/null || die "the signing certificate has expired."
    CERT_CN="$(cmd_signer)"
    log "certificate: $(openssl x509 -inform DER -in "${CERT_DER}" -noout -subject -serial -dates -nameopt RFC2253 | tr '\n' ' ')"
    log "certificate SHA-256: ${fp}; kernel-reported signer (issuer CN): '${CERT_CN}'"
    [ -z "${GPU_MODULE_SIGN_CERT_SHA256:-}" ] || log "certificate matches the pinned GPU_MODULE_SIGN_CERT_SHA256."
}

cert_fp() { openssl dgst -sha256 -binary "${CERT_DER}" | od -An -vtx1 | tr -d ' \n'; }

load_key() {
    [ -n "${KEY_PEM}" ] && return 0
    load_cert
    local raw="${WORK}/key.raw"
    if [ -n "${GPU_MODULE_SIGN_KEY_FILE:-}" ]; then
        [ -s "${GPU_MODULE_SIGN_KEY_FILE}" ] || die "GPU_MODULE_SIGN_KEY_FILE='${GPU_MODULE_SIGN_KEY_FILE}' is missing or empty."
        cp "${GPU_MODULE_SIGN_KEY_FILE}" "${raw}"
    elif [ -n "${MOK_PRIV:-}" ]; then
        content_to_file "${MOK_PRIV}" "${raw}"
    else
        die "no signing key: set MOK_PRIV (content) or GPU_MODULE_SIGN_KEY_FILE (path). Refusing to build unsigned GPU modules."
    fi
    if is_pem "${raw}"; then
        openssl pkey -in "${raw}" -out "${WORK}/key.pem" 2>/dev/null || die "cannot parse the PEM private key (encrypted keys are not supported)."
    else
        openssl pkey -inform DER -in "${raw}" -out "${WORK}/key.pem" 2>/dev/null || die "cannot parse the private key (not PEM, not DER)."
    fi
    rm -f "${raw}"
    KEY_PEM="${WORK}/key.pem"
    # The key must be the certificate's key.
    local a b
    a="$(openssl x509 -inform DER -in "${CERT_DER}" -noout -pubkey)"
    b="$(openssl pkey -in "${KEY_PEM}" -pubout)"
    [ "${a}" = "${b}" ] || die "the private key does not match the certificate (MOK_PRIV and MOK_DER are not a pair)."
    log "signing key loaded: $(openssl pkey -in "${KEY_PEM}" -noout -text 2>/dev/null | head -1 | sed 's/^Private-Key: //'); its public key matches the certificate."
}

# ---------------------------------------------------------------------------
# Module signature trailer
# ---------------------------------------------------------------------------
MAGICLEN=$(( ${#MAGIC} + 1 ))   # the magic string is followed by a newline

has_magic() {
    local f="$1" size
    size=$(wc -c < "$f" | tr -d ' ')
    [ "${size}" -gt "${MAGICLEN}" ] || return 1
    tail -c "${MAGICLEN}" "$f" | cmp -s - <(printf '%s\n' "${MAGIC}")
}

# split_module <module> <body-out> <sig-out>
split_module() {
    local f="$1" size siglen hdr body
    size=$(wc -c < "$f" | tr -d ' ')
    siglen=$(( 16#$(tail -c $(( MAGICLEN + SIGLEN_BYTES )) "$f" | head -c ${SIGLEN_BYTES} | od -An -vtx1 | tr -d ' \n') ))
    [ "${siglen}" -gt 0 ] && [ $(( siglen + 12 + MAGICLEN )) -lt "${size}" ] || return 2
    # The kernel rejects anything but algo=0, hash=0, id_type=2 (PKCS#7), signer_len=0, key_id_len=0, pad=0.
    hdr="$(tail -c $(( MAGICLEN + 12 )) "$f" | head -c 8 | od -An -vtx1 | tr -d ' \n')"
    [ "${hdr}" = "0000020000000000" ] || return 2
    body=$(( size - MAGICLEN - 12 - siglen ))
    head -c "${body}" "$f" > "$2"
    tail -c $(( MAGICLEN + 12 + siglen )) "$f" | head -c "${siglen}" > "$3"
}

be32() { # print 4 big-endian bytes of $1
    local n="$1" i
    for i in 24 16 8 0; do
        printf "\\$(printf '%03o' $(( (n >> i) & 255 )))"
    done
}

# ---------------------------------------------------------------------------
# Compression helpers
# ---------------------------------------------------------------------------
mod_kind() {
    case "$1" in
        *.ko.zst) echo zst ;;
        *.ko.xz)  echo xz ;;
        *.ko.gz)  echo gz ;;
        *.ko)     echo ko ;;
        *) return 1 ;;
    esac
}

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required to handle $2 modules."; }

decompress() { # <module> <out>
    case "$(mod_kind "$1")" in
        ko)  cp "$1" "$2" ;;
        zst) need zstd .zst; zstd -d -q -f -o "$2" "$1" ;;
        xz)  need xz .xz;   xz -d -c "$1" > "$2" ;;
        gz)  need gzip .gz; gzip -d -c "$1" > "$2" ;;
    esac
}

recompress() { # <in> <module-to-replace>
    local tmp; tmp="$(mktemp "$(dirname "$2")/.modsign.XXXXXX")"
    case "$(mod_kind "$2")" in
        ko)  cp "$1" "${tmp}" ;;
        zst) zstd -q -f -o "${tmp}" "$1" ;;
        xz)  xz --check=crc32 -c "$1" > "${tmp}" ;;
        gz)  gzip -n -c "$1" > "${tmp}" ;;
    esac
    chmod --reference="$2" "${tmp}" 2>/dev/null || chmod 0644 "${tmp}"
    mv -f "${tmp}" "$2"
}

list_modules() {
    local p
    for p in "$@"; do
        if [ -d "$p" ]; then
            find "$p" -type f \( -name '*.ko' -o -name '*.ko.zst' -o -name '*.ko.xz' -o -name '*.ko.gz' \) | sort
        elif [ -f "$p" ]; then
            printf '%s\n' "$p"
        else
            die "no such file or directory: $p"
        fi
    done
}

# ---------------------------------------------------------------------------
# sign / verify
# ---------------------------------------------------------------------------
find_sign_file() {
    local kver="$1" c
    if [ -n "${SIGN_FILE:-}" ]; then
        [ -x "${SIGN_FILE}" ] && { echo "${SIGN_FILE}"; return 0; }
        die "SIGN_FILE='${SIGN_FILE}' is not executable."
    fi
    for c in "/usr/src/linux-headers-${kver}/scripts/sign-file" \
             "/lib/modules/${kver}/build/scripts/sign-file" \
             "/usr/lib/linux-kbuild-${kver%%-*}/scripts/sign-file"; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

# Name a signature file says it was made by (the issuer CN of its SignerInfo), or empty.
sig_signer_cn() {
    openssl asn1parse -inform DER -in "$1" 2>/dev/null | awk '/commonName/ {getline; sub(/.*:/, ""); print; exit}'
}

sign_one() { # <kver> <sign-file-or-empty> <module>
    local kver="$1" sf="$2" m="$3" body="${BIG}/body.ko" sig="${BIG}/sig.der" prev="none (unsigned)" size
    decompress "$m" "${body}"
    if has_magic "${body}"; then
        split_module "${body}" "${BIG}/stripped.ko" "${sig}" || die "$m: has a malformed signature trailer."
        prev="signed by '$(sig_signer_cn "${sig}")' (not our key; replacing it)"
        mv -f "${BIG}/stripped.ko" "${body}"
    fi
    size=$(wc -c < "${body}" | tr -d ' ')
    log "signing ${m##*/}: previous signature: ${prev}; ${size} bytes unsigned; method: $([ -n "${sf}" ] && echo sign-file || echo openssl)"
    dbg "${m##*/}: unsigned module SHA-256 $(openssl dgst -sha256 "${body}" | sed 's/.*= //')"
    if [ -n "${sf}" ]; then
        "${sf}" sha256 "${KEY_PEM}" "${CERT_DER}" "${body}" || die "$m: sign-file failed."
    else
        openssl cms -sign -binary -noattr -nocerts -md sha256 -in "${body}" \
            -signer "${CERT_PEM}" -inkey "${KEY_PEM}" -outform DER -out "${sig}" \
            || die "$m: openssl could not sign the module."
        {
            cat "${body}"; cat "${sig}"
            printf '\0\0\2\0\0\0\0\0'
            be32 "$(wc -c < "${sig}" | tr -d ' ')"
            printf '%s\n' "${MAGIC}"
        } > "${BIG}/signed.ko"
        mv -f "${BIG}/signed.ko" "${body}"
    fi
    dbg "${m##*/}: signed module is $(wc -c < "${body}" | tr -d ' ') bytes (signature + trailer added: $(( $(wc -c < "${body}" | tr -d ' ') - size )) bytes)"
    recompress "${body}" "$m"
    rm -f "${body}" "${sig}"
    log "SIGNED    ${m##*/} -> signer '${CERT_CN}'"
}

verify_one() { # <module> -> 0 ok, 1 unsigned / bad
    local m="$1" body="${BIG}/vbody.ko" content="${BIG}/vcontent.ko" sig="${BIG}/vsig.der" rc=0
    decompress "$m" "${body}" || die "$m: could not unpack the module (disk full in ${BIG}?)."
    if ! has_magic "${body}"; then
        echo "UNSIGNED  $m (no module signature)" >&2; rm -f "${body}"; return 1
    fi
    local srr=0
    split_module "${body}" "${content}" "${sig}" || srr=$?
    if [ "${srr}" -ne 0 ]; then
        echo "MALFORMED $m (bad signature trailer, or a write failed: $(df -h "${BIG}" 2>/dev/null | awk 'NR==2 {print $4" free in "$6}'))" >&2; rm -f "${body}"; return 1
    fi
    if openssl cms -verify -binary -inform DER -in "${sig}" -content "${content}" \
            -certfile "${CERT_PEM}" -noverify -nointern -purpose any -out /dev/null 2>/dev/null; then
        echo "OK        $m  signer='${CERT_CN}'"
        dbg "${m##*/}: signature is $(wc -c < "${sig}" | tr -d ' ') bytes"
    else
        echo "BADSIG    $m (signature names '$(sig_signer_cn "${sig}")', which does not verify against the pinned certificate '${CERT_CN}')" >&2; rc=1
    fi
    rm -f "${body}" "${content}" "${sig}"
    return ${rc}
}

cmd_verify() {
    [ -n "${MODE}" ] || MODE=verify
    [ $# -ge 1 ] || die "verify: give at least one directory or module."
    load_cert
    mk_workdir
    local mods bad=0 n=0 m
    mods="$(list_modules "$@")"
    [ -n "${mods}" ] || die "verify: no kernel modules found under: $*"
    while IFS= read -r m; do
        n=$((n + 1))
        verify_one "$m" || bad=$((bad + 1))
    done <<< "${mods}"
    [ "${bad}" -eq 0 ] || die "${bad} of ${n} module(s) are unsigned or not signed by the expected certificate (SHA-256 $(cert_fp))."
    log "all ${n} module(s) verified against certificate SHA-256 $(cert_fp)."
    [ "${MODE}" != "verify" ] || log "GPU MODULE SIGNING: SUCCESS (verify): ${n} module(s) carry a valid signature from '${CERT_CN}' (cert SHA-256 $(cert_fp))"
}

cmd_sign() {
    MODE=sign
    [ $# -ge 2 ] || die "sign: usage: sign <kver> <dir|module>..."
    local kver="$1" sf="" mods m n=0 method=openssl; shift
    load_key
    if sf="$(find_sign_file "${kver}")"; then
        log "signing with the kernel's sign-file: ${sf}"
        method=sign-file
    else
        sf=""
        log "no sign-file for kernel ${kver}; signing with openssl (same module-signature layout)."
    fi
    mods="$(list_modules "$@")"
    [ -n "${mods}" ] || die "sign: no kernel modules found under: $*"
    while IFS= read -r m; do
        sign_one "${kver}" "${sf}" "$m"
        n=$((n + 1))
    done <<< "${mods}"
    log "signed ${n} module(s); verifying what was written ..."
    cmd_verify "$@"
    log "GPU MODULE SIGNING: SUCCESS (sign): ${n} module(s) signed by '${CERT_CN}' with ${method} and verified (cert SHA-256 $(cert_fp))"
    if [ -n "${GPU_MODULE_SIGN_STATUS_FILE:-}" ]; then
        mkdir -p "$(dirname "${GPU_MODULE_SIGN_STATUS_FILE}")"
        {
            echo "status=signed"
            echo "modules=${n}"
            echo "signer=${CERT_CN}"
            echo "cert_sha256=$(cert_fp)"
            echo "method=${method}"
            echo "kernel=${kver}"
            echo "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        } > "${GPU_MODULE_SIGN_STATUS_FILE}"
        chmod 0644 "${GPU_MODULE_SIGN_STATUS_FILE}"
        log "wrote signing status record ${GPU_MODULE_SIGN_STATUS_FILE}"
    fi
}

cmd_signer() {
    load_cert
    # With no certificate inside the signature, the kernel (and modinfo) report the issuer's CN.
    openssl x509 -inform DER -in "${CERT_DER}" -noout -issuer -nameopt multiline \
        | awk -F' = ' '/commonName/ {print $2; exit}'
}

[ $# -ge 1 ] || { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
mode="$1"; shift
case "${mode}" in
    sign)        cmd_sign "$@" ;;
    verify)      cmd_verify "$@" ;;
    fingerprint) load_cert; cert_fp; echo ;;
    signer)      cmd_signer ;;
    check-key)   load_key; log "signing key and certificate are present and match (cert SHA-256 $(cert_fp))." ;;
    export-cert) [ $# -eq 1 ] || die "export-cert: usage: export-cert <file>"; load_cert; mkdir -p "$(dirname "$1")"; cp "${CERT_DER}" "$1"; chmod 0644 "$1" ;;
    *) die "unknown subcommand '${mode}' (use sign, verify, fingerprint, signer, export-cert, check-key)." ;;
esac
