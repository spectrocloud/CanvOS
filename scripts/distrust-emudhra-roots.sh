#!/bin/sh
#
# distrust-emudhra-roots.sh - remove the CA roots that chain to the compromised
# eMudhra intermediate certificates, and prove that they are gone.
#
# Mozilla bugs 2083449 and 2084101.
#
# Design
#   Policy  : a list of root labels. The default is the three roots named by Mozilla.
#   Action  : label based. Debian deselects the entry in /etc/ca-certificates.conf;
#             SUSE and RHEL extract the certificate by label into the blacklist directory.
#   Verdict : certificate based. Verification compares the SHA-256 of the
#             SubjectPublicKeyInfo of every trusted anchor with the known values.
#             A label, file name or certificate encoding change therefore fails the
#             build instead of silently leaving the root trusted.
#
# Usage
#   distrust-emudhra-roots.sh                       apply the default policy, then verify
#   distrust-emudhra-roots.sh --labels "A;B"        apply a subset, then verify
#   distrust-emudhra-roots.sh --check               verify the effective policy only
#   distrust-emudhra-roots.sh --labels "A" --check  verify a specific policy
#
# Environment
#   EMUDHRA_ALLOW_MISSING_STORE=1   do not fail when no trust store is found
#   EMUDHRA_STATE_FILE=path         file that records the effective policy
#                                   (default: /etc/spectrocloud/distrust-emudhra.targets)
#
set -eu

PROG=${0##*/}
CHECK_ONLY=0
REQUESTED_LABELS=
ALLOW_MISSING_STORE=${EMUDHRA_ALLOW_MISSING_STORE:-0}
STATE_FILE=${EMUDHRA_STATE_FILE:-/etc/spectrocloud/distrust-emudhra.targets}

# Known roots: label | SPKI SHA-256.  The Debian entry is derived from the label.
KNOWN_ROOTS='emSign ECC Root CA - G3|8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782
emSign Root TLS CA - G3|c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9
Comodo AAA Services root|bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3'

log()  { printf '%s: %s\n' "$PROG" "$*"; }
warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }
usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

while [ $# -gt 0 ]; do
    case $1 in
        --check) CHECK_ONLY=1 ;;
        --labels) shift; [ $# -gt 0 ] || die "--labels needs a value"; REQUESTED_LABELS=$1 ;;
        --labels=*) REQUESTED_LABELS=${1#*=} ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/emudhra.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'rm -rf "$WORK"; exit 130' HUP INT TERM

# ---------------------------------------------------------------------------
# Known roots
# ---------------------------------------------------------------------------

known_labels() { printf '%s\n' "$KNOWN_ROOTS" | cut -d'|' -f1; }

spki_of_label() {
    printf '%s\n' "$KNOWN_ROOTS" | awk -F'|' -v l="$1" '$1 == l { print $2; exit }'
}

# Debian names an entry after its label, with spaces as underscores.
conf_entry_of_label() {
    printf 'mozilla/%s.crt\n' "$(printf '%s' "$1" | tr ' ' '_')"
}

is_known_label() {
    printf '%s\n' "$KNOWN_ROOTS" | awk -F'|' -v l="$1" '$1 == l { found = 1 } END { exit(found ? 0 : 1) }'
}

# Turn a ';' separated list into a canonical newline separated list.
# Unknown labels are a hard error: a typo must not disable the control.
parse_labels() {
    _in=$1
    _out=$2
    printf '%s' "$_in" | tr ';' '\n' > "$WORK/labels.raw"
    : > "$_out"
    while IFS= read -r _raw; do
        _label=$(printf '%s' "$_raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$_label" ] || continue
        if ! is_known_label "$_label"; then
            warn "unknown label: $_label"
            warn "known labels: $(known_labels | tr '\n' ' ')"
            return 1
        fi
        printf '%s\n' "$_label" >> "$_out"
    done < "$WORK/labels.raw"
    awk '!seen[$0]++' "$_out" > "$_out.tmp"
    mv "$_out.tmp" "$_out"
    [ -s "$_out" ]
}

# Write the effective policy to $WORK/effective.txt.
effective_labels() {
    if [ -n "$REQUESTED_LABELS" ]; then
        parse_labels "$REQUESTED_LABELS" "$WORK/effective.txt" || exit 2
    elif [ -f "$STATE_FILE" ]; then
        _state=$(tr '\n' ';' < "$STATE_FILE")
        parse_labels "$_state" "$WORK/effective.txt" || exit 2
    else
        default_labels
    fi
}

default_labels() {
    known_labels > "$WORK/effective.txt"
}

# ---------------------------------------------------------------------------
# Trust store detection and helpers
# ---------------------------------------------------------------------------

detect_family() {
    if [ -d /etc/pki/ca-trust ] && command -v update-ca-trust >/dev/null 2>&1; then
        echo rhel
    elif [ -d /etc/pki/trust ] && command -v update-ca-certificates >/dev/null 2>&1; then
        echo suse
    elif [ -f /etc/ca-certificates.conf ] && command -v update-ca-certificates >/dev/null 2>&1; then
        echo debian
    else
        echo unknown
    fi
}

rhel_blocklist_dir() {
    if [ -d /etc/pki/ca-trust/source/blacklist ]; then
        echo /etc/pki/ca-trust/source/blacklist
    else
        echo /etc/pki/ca-trust/source/blocklist
    fi
}

percent_encode() {
    printf '%s' "$1" | od -An -tx1 | tr -d ' \n' | sed 's/../%&/g'
}

# ---------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------

apply_debian() {
    _conf=/etc/ca-certificates.conf
    [ -f "$_conf" ] || { warn "$_conf is missing"; return 1; }

    # Normalise every line: CRLF and surrounding whitespace break the lookup.
    _tmp=$WORK/ca-certificates.conf
    : > "$_tmp"
    while IFS= read -r _raw || [ -n "$_raw" ]; do
        printf '%s\n' "$(printf '%s' "$_raw" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" >> "$_tmp"
    done < "$_conf"

    while IFS= read -r _label; do
        _entry=$(conf_entry_of_label "$_label")
        if grep -F -x -q "$_entry" "$_tmp"; then
            awk -v e="$_entry" '$0 == e { print "!" e; next } { print }' "$_tmp" > "$_tmp.new"
            mv "$_tmp.new" "$_tmp"
        fi
        if ! grep -F -x -q "!$_entry" "$_tmp"; then
            printf '!%s\n' "$_entry" >> "$_tmp"
        fi
    done < "$WORK/effective.txt"

    cat "$_tmp" > "$_conf"
    update-ca-certificates --fresh
}

apply_p11kit() {
    _dir=$1
    mkdir -p "$_dir"
    while IFS= read -r _label; do
        _enc=$(percent_encode "$_label")
        _out="$_dir/$(printf '%s' "$_label" | tr ' ' '_').pem"
        if trust extract --format=pem-bundle --filter="pkcs11:object=$_enc;type=cert" \
                --overwrite "$_out" >/dev/null 2>&1 && [ -s "$_out" ]; then
            chmod 0644 "$_out"
            log "blocklisted: $_label"
        else
            rm -f "$_out"
            warn "label not found in the trust store: $_label (the verifier decides)"
        fi
    done < "$WORK/effective.txt"
}

apply_store() {
    case $1 in
        debian)
            log "trust store family: debian"
            apply_debian
            ;;
        suse)
            log "trust store family: suse"
            apply_p11kit /etc/pki/trust/blacklist || return 1
            update-ca-certificates
            ;;
        rhel)
            log "trust store family: rhel"
            apply_p11kit "$(rhel_blocklist_dir)" || return 1
            update-ca-trust
            ;;
        *)
            return 1
            ;;
    esac
}

write_state() {
    _dir=$(dirname "$STATE_FILE")
    mkdir -p "$_dir" 2>/dev/null || true
    if cp "$WORK/effective.txt" "$STATE_FILE" 2>/dev/null; then
        chmod 0644 "$STATE_FILE" 2>/dev/null || true
    else
        warn "could not record the effective policy in $STATE_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

have_openssl() { command -v openssl >/dev/null 2>&1; }

spki_of_cert() {
    openssl x509 -in "$1" -noout -pubkey 2>/dev/null \
        | openssl pkey -pubin -outform DER 2>/dev/null \
        | openssl dgst -sha256 -r 2>/dev/null \
        | awk '{ print $1 }'
}

split_pem() {
    _file=$1
    _dir=$2
    rm -rf "$_dir"
    mkdir -p "$_dir"
    awk -v dir="$_dir" '
        /-----BEGIN [A-Z ]*CERTIFICATE-----/ { n++; f = dir "/c-" n ".pem"; inb = 1 }
        inb { print > f }
        /-----END [A-Z ]*CERTIFICATE-----/ { inb = 0; if (f != "") close(f) }
    ' "$_file"
}

dir_has_spki() {
    _dir=$1
    _spki=$2
    for _f in "$_dir"/*; do
        [ -f "$_f" ] || continue
        [ "$(spki_of_cert "$_f")" = "$_spki" ] && return 0
    done
    return 1
}

# Build the list of places that can hold a trusted anchor.
collect_anchor_dirs() {
    : > "$WORK/anchor-dirs"
    if [ "$FAMILY" = "debian" ] && [ -d /etc/ssl/certs ]; then
        rm -rf "$WORK/debian-links"
        mkdir -p "$WORK/debian-links"
        for _f in /etc/ssl/certs/[0-9a-f]*.[0-9]*; do
            [ -f "$_f" ] && cp -L "$_f" "$WORK/debian-links/" 2>/dev/null || true
        done
        printf '%s\n' "$WORK/debian-links" >> "$WORK/anchor-dirs"
    fi
    if [ "$FAMILY" != "debian" ] && command -v trust >/dev/null 2>&1; then
        if trust extract --format=pem-bundle --filter=ca-anchors --overwrite "$WORK/anchors.pem" >/dev/null 2>&1 \
                && [ -s "$WORK/anchors.pem" ]; then
            split_pem "$WORK/anchors.pem" "$WORK/anchors"
            printf '%s\n' "$WORK/anchors" >> "$WORK/anchor-dirs"
        fi
    fi
    _n=0
    for _b in /etc/ssl/certs/ca-certificates.crt \
              /etc/ssl/ca-bundle.pem \
              /var/lib/ca-certificates/ca-bundle.pem \
              /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
        [ -f "$_b" ] || continue
        _n=$((_n + 1))
        split_pem "$_b" "$WORK/bundle-$_n"
        printf '%s\n' "$WORK/bundle-$_n" >> "$WORK/anchor-dirs"
    done
}

# Fallback when openssl is absent: ask the store by name.
fallback_has_label() {
    _label=$1
    if [ "$FAMILY" = "debian" ]; then
        _link=$(printf '%s' "$_label" | tr ' ' '_').pem
        [ -e "/etc/ssl/certs/$_link" ] && return 0
        return 1
    fi
    if command -v trust >/dev/null 2>&1; then
        if ! _list=$(trust list --filter=ca-anchors 2>/dev/null); then
            warn "trust list failed, cannot verify $_label"
            return 2
        fi
        printf '%s\n' "$_list" | grep -F -q "    label: $_label"
        return $?
    fi
    return 2
}

verify_targets() {
    _rc=0
    NO_STORE=0
    collect_anchor_dirs
    _checked=0

    while IFS= read -r _dir; do
        [ -d "$_dir" ] && _checked=1
    done < "$WORK/anchor-dirs"

    if have_openssl; then
        while IFS= read -r _label; do
            _spki=$(spki_of_label "$_label")
            _found=0
            while IFS= read -r _dir; do
                if dir_has_spki "$_dir" "$_spki"; then
                    _found=1
                    break
                fi
            done < "$WORK/anchor-dirs"
            if [ "$_found" = "1" ]; then
                warn "still trusted: $_label (SPKI $_spki)"
                _rc=1
            fi
        done < "$WORK/effective.txt"
    else
        warn "openssl is not available, verification falls back to store names"
        while IFS= read -r _label; do
            fallback_has_label "$_label"
            case $? in
                0) warn "still trusted: $_label"; _rc=1 ;;
                2) warn "could not query the trust store for $_label"; _rc=1 ;;
            esac
        done < "$WORK/effective.txt"
    fi

    if [ "$_checked" = "0" ]; then
        warn "no system CA bundle or anchor set found"
        NO_STORE=1
        _rc=1
    fi
    return $_rc
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

FAMILY=$(detect_family)

effective_labels

if [ "$CHECK_ONLY" = "1" ]; then
    if verify_targets; then
        log "OK: none of the selected roots is trusted"
        exit 0
    fi
    if [ "$NO_STORE" = "1" ] && [ "$ALLOW_MISSING_STORE" = "1" ]; then
        warn "no trust store to check, accepting EMUDHRA_ALLOW_MISSING_STORE=1"
        exit 0
    fi
    exit 1
fi

if [ "$FAMILY" = "unknown" ]; then
    warn "unknown trust store layout"
    if [ "$ALLOW_MISSING_STORE" = "1" ]; then
        warn "continuing because EMUDHRA_ALLOW_MISSING_STORE=1"
        if verify_targets; then
            exit 0
        fi
        if [ "$NO_STORE" = "1" ]; then
            exit 0
        fi
        exit 1
    fi
    exit 1
fi

apply_store "$FAMILY"
write_state

if verify_targets; then
    log "OK: the selected roots are not trusted"
else
    warn "verification failed"
    exit 1
fi
