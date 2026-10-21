#!/bin/sh
#
# distrust-emudhra-roots.sh - remove the roots compromised in the eMudhra incident.
#
# Mozilla Bugzilla 2083449: the private keys of eight eMudhra intermediate
# certificates are compromised.  Three roots can chain to those intermediates:
#
#   emSign ECC Root CA - G3    SPKI sha256 8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782
#   emSign Root TLS CA - G3    SPKI sha256 c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9
#   AAA Certificate Services   SPKI sha256 bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3
#
# The script distrusts all three in whichever trust store the image uses:
#
#   Debian family (Ubuntu, Hadron)  prefix the entry in /etc/ca-certificates.conf
#                                   with "!" and run update-ca-certificates
#   SUSE family (openSUSE, SLES)    write the certificate into /etc/pki/trust/blacklist
#                                   and run update-ca-certificates
#   RHEL family (RHEL, UBI)         write the certificate into
#                                   /etc/pki/ca-trust/source/blocklist and run update-ca-trust
#
# The three certificates are embedded, so the script needs no network access and
# works even when the base image no longer ships a root.  The script is idempotent.
#
# The eight compromised intermediates cannot be blocked by the trust tools in
# these images.  An intermediate arrives from the peer and the store only
# contributes anchors: RHEL writes the reject record only into the legacy
# ca-bundle.trust.crt, SUSE keeps it in the p11-kit database but emits nothing
# into /etc/ssl/certs, and Debian has no distrust mechanism for non-anchors.
# None of the bundles that OpenSSL, Go or containerd load carry the record.
# Removing the three roots is the only reliable store-level mitigation.
# See Mozilla bug 2083449.
#
# Usage:
#   distrust-emudhra-roots.sh           apply the change and verify it
#   distrust-emudhra-roots.sh --check   verify only; exit 1 if a root is still trusted
#
# Environment:
#   EMUDHRA_KEEP_AAA=1   keep AAA Certificate Services trusted.  Use this only
#                        when the host must keep legacy Sectigo chains.  The AAA
#                        cross-sign of the compromised intermediates stays
#                        exploitable while AAA is trusted.

set -eu

PROG=${0##*/}
CHECK_ONLY=0
KEEP_AAA=${EMUDHRA_KEEP_AAA:-0}

case "${1:-}" in
    --check) CHECK_ONLY=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    "") ;;
    *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
esac

WORK=${TMPDIR:-/tmp}/emudhra-distrust.$$
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

G3_PEM=$WORK/emSign_ECC_Root_CA_-_G3.pem
TLS_PEM=$WORK/emSign_Root_TLS_CA_-_G3.pem
AAA_PEM=$WORK/AAA_Certificate_Services.pem

cat > "$G3_PEM" <<'PEM_G3'
-----BEGIN CERTIFICATE-----
MIICTjCCAdOgAwIBAgIKPPYHqWhwDtqLhDAKBggqhkjOPQQDAzBrMQswCQYDVQQG
EwJJTjETMBEGA1UECxMKZW1TaWduIFBLSTElMCMGA1UEChMcZU11ZGhyYSBUZWNo
bm9sb2dpZXMgTGltaXRlZDEgMB4GA1UEAxMXZW1TaWduIEVDQyBSb290IENBIC0g
RzMwHhcNMTgwMjE4MTgzMDAwWhcNNDMwMjE4MTgzMDAwWjBrMQswCQYDVQQGEwJJ
TjETMBEGA1UECxMKZW1TaWduIFBLSTElMCMGA1UEChMcZU11ZGhyYSBUZWNobm9s
b2dpZXMgTGltaXRlZDEgMB4GA1UEAxMXZW1TaWduIEVDQyBSb290IENBIC0gRzMw
djAQBgcqhkjOPQIBBgUrgQQAIgNiAAQjpQy4LRL1KPOxst3iAhKAnjlfSU2fySU0
WXTsuwYc58Byr+iuL+FBVIcUqEqy6HyC5ltqtdyzdc6LBtCGI79G1Y4PPwT01xyS
fvalY8L1X44uT6EYGQIrMgqCZH0Wk9GjQjBAMB0GA1UdDgQWBBR8XQKEE9TMipuB
zhccLikenEhjQjAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAKBggq
hkjOPQQDAwNpADBmAjEAvvNhzwIQHWSVB7gYboiFBS+DCBeQyh+KTOgNG3qxrdWB
CUfvO6wIBHxcmbHtRwfSAjEAnbpV/KlK6O3t5nYBQnvI+GDZjVGLVTv7jHvrZQnD
+JbNR6iC8hZVdyR+EhCVBCyj
-----END CERTIFICATE-----
PEM_G3

cat > "$TLS_PEM" <<'PEM_TLS'
-----BEGIN CERTIFICATE-----
MIICKTCCAa+gAwIBAgIQDnYGcvFDRZ/I/gqwvAXjlDAKBggqhkjOPQQDAzBWMQsw
CQYDVQQGEwJJTjElMCMGA1UECgwcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRl
ZDEgMB4GA1UEAwwXZW1TaWduIFJvb3QgVExTIENBIC0gRzMwHhcNMjQwMjA4MDgx
OTMyWhcNNDkwMjA3MDgxOTMyWjBWMQswCQYDVQQGEwJJTjElMCMGA1UECgwcZU11
ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRlZDEgMB4GA1UEAwwXZW1TaWduIFJvb3Qg
VExTIENBIC0gRzMwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAARfD9w/q1cWxL6D9bMG
H6CQ4u+gAV6GN9s+PwQx9Bl4hC+0iU8QOk8mWO/RwXQy10DCSxT8vSIJClHKp+Ao
4qJKdYeV0SwZ7LMQziyLfxIUOY6Grja/sQFwLKYf8EdDXAyjQjBAMB0GA1UdDgQW
BBThOqshfPHjTVSu1HK3/YtZQiCQVDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/
BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjBhCFTkly7Yl7+s4hiw+k6ZJTXT2AiI
rvmsmfqPr5E7ecwXb6kXA5LTFd6rjwTuV3sCMQC9w6ZSbVq1mveMO6dKFziOzClT
KCT2RFT6yXtq6nzgRICgBmiXbJAXsmZ8yAwjyWc=
-----END CERTIFICATE-----
PEM_TLS

cat > "$AAA_PEM" <<'PEM_AAA'
-----BEGIN CERTIFICATE-----
MIIEMjCCAxqgAwIBAgIBATANBgkqhkiG9w0BAQUFADB7MQswCQYDVQQGEwJHQjEb
MBkGA1UECAwSR3JlYXRlciBNYW5jaGVzdGVyMRAwDgYDVQQHDAdTYWxmb3JkMRow
GAYDVQQKDBFDb21vZG8gQ0EgTGltaXRlZDEhMB8GA1UEAwwYQUFBIENlcnRpZmlj
YXRlIFNlcnZpY2VzMB4XDTA0MDEwMTAwMDAwMFoXDTI4MTIzMTIzNTk1OVowezEL
MAkGA1UEBhMCR0IxGzAZBgNVBAgMEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UE
BwwHU2FsZm9yZDEaMBgGA1UECgwRQ29tb2RvIENBIExpbWl0ZWQxITAfBgNVBAMM
GEFBQSBDZXJ0aWZpY2F0ZSBTZXJ2aWNlczCCASIwDQYJKoZIhvcNAQEBBQADggEP
ADCCAQoCggEBAL5AnfRu4ep2hxxNRUSOvkbIgwadwSr+GB+O5AL686tdUIoWMQua
BtDFcCLNSS1UY8y2bmhGC1Pqy0wkwLxyTurxFa70VJoSCsN6sjNg4tqJVfMiWPPe
3M/vg4aijJRPn2jymJBGhCfHdr/jzDUsi14HZGWCwEiwqJH5YZ92IFCokcdmtet4
YgNW8IoaE+oxox6gmf049vYnMlhvB/VruPsUK6+3qszWY19zjNoFmag4qMsXeDZR
rOme9Hg6jc8P2ULimAyrL58OAd7vn5lJ8S3frHRNG5i1R8XlKdH5kBjHYpy+g8cm
ez6KJcfA3Z3mNWgQIJ2P2N7Sw4ScDV7oL8kCAwEAAaOBwDCBvTAdBgNVHQ4EFgQU
oBEKIz6W8Qfs4q8p74Klf9AwpLQwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQF
MAMBAf8wewYDVR0fBHQwcjA4oDagNIYyaHR0cDovL2NybC5jb21vZG9jYS5jb20v
QUFBQ2VydGlmaWNhdGVTZXJ2aWNlcy5jcmwwNqA0oDKGMGh0dHA6Ly9jcmwuY29t
b2RvLm5ldC9BQUFDZXJ0aWZpY2F0ZVNlcnZpY2VzLmNybDANBgkqhkiG9w0BAQUF
AAOCAQEACFb8AvCb6P+k+tZ7xkSAzk/ExfYAWMymtrwUSWgEdujm7l3sAg9g1o1Q
GE8mTgHj5rCl7r+8dFRBv/38ErjHT1r0iWAFf2C3BUrz9vHCv8S5dIa2LX1rzNLz
Rt0vxuBqw8M0Ayx9lt1awg6nCpnBBYurDC/zXDrPbDdVCYfeU0BsWO/8tqtlbgT2
G9w84FoVxp7Z8VlIMCFlA2zs6SFz7JsDoeA3raAVGI/6ugLOpyypEBMs1OUIJqsi
l2D4kF501KKaU73yqWjgom7C12yxow+ev+to51byrvLjKzg6CYG1a4XXvi3tPxq3
smPi9WIsgtRqAEFQ8TmDn5XpNpaYbg==
-----END CERTIFICATE-----
PEM_AAA

# The target list is newline separated and read through a file, so paths that
# contain spaces are safe.
printf '%s\n' "$G3_PEM" "$TLS_PEM" > "$WORK/targets.lst"
if [ "$KEEP_AAA" = "1" ]; then
    echo "$PROG: EMUDHRA_KEEP_AAA=1, AAA Certificate Services stays trusted" >&2
else
    printf '%s\n' "$AAA_PEM" >> "$WORK/targets.lst"
fi

# norm_certs prints one line per certificate in the file: the base64 body with
# all whitespace removed.  It works for CERTIFICATE and TRUSTED CERTIFICATE
# blocks and needs no external parser.
norm_certs() {
    awk '
        /-----BEGIN [A-Z ]*CERTIFICATE-----/ { inb = 1; buf = ""; next }
        /-----END [A-Z ]*CERTIFICATE-----/   { if (inb && buf != "") print buf; inb = 0; buf = ""; next }
        inb { gsub(/[[:space:]]/, ""); buf = buf $0 }
    ' "$1"
}

: > "$WORK/targets.bodies"
while IFS= read -r pem; do
    norm_certs "$pem" >> "$WORK/targets.bodies"
done < "$WORK/targets.lst"

bundle_trusts_target() {
    norm_certs "$1" > "$WORK/scan.bodies"
    grep -F -x -q -f "$WORK/targets.bodies" "$WORK/scan.bodies"
}

cert_file_is_target() {
    norm_certs "$1" > "$WORK/one.body"
    [ -s "$WORK/one.body" ] || return 1
    grep -F -x -q -f "$WORK/targets.bodies" "$WORK/one.body"
}

# Debian file names come from the certificate label and differ between
# distributions (Ubuntu 20.04 calls the AAA root Comodo_AAA_Services_root.crt).
# Match the known names as a fallback for stores whose copy is not byte identical.
name_is_target() {
    case $(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') in
        *emsign_ecc_root_ca_-_g3*|*emsign_root_tls_ca_-_g3*) return 0 ;;
        *aaa_certificate_services*|*comodo_aaa_services_root*)
            [ "$KEEP_AAA" = "1" ] && return 1
            return 0
            ;;
    esac
    return 1
}

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

apply_debian() {
    conf=/etc/ca-certificates.conf
    base=/usr/share/ca-certificates
    new=$WORK/ca-certificates.conf

    if [ ! -f "$conf" ]; then
        echo "$PROG: $conf is missing, cannot apply the Debian style change" >&2
        return 1
    fi

    changed=0
    : > "$new"
    while IFS= read -r line || [ -n "$line" ]; do
        out=$line
        case $line in
            ''|'#'*|'!'*) ;;
            *)
                if [ -f "$base/$line" ] && { cert_file_is_target "$base/$line" || name_is_target "$line"; }; then
                    out="!$line"
                    changed=1
                fi
                ;;
        esac
        printf '%s\n' "$out" >> "$new"
    done < "$conf"

    if [ "$changed" = "1" ]; then
        cat "$new" > "$conf"
        echo "$PROG: deselected the revoked roots in $conf"
    else
        echo "$PROG: no revoked root is listed in $conf"
    fi

    update-ca-certificates
}

install_blocklist() {
    dir=$1
    mkdir -p "$dir"
    while IFS= read -r pem; do
        cp "$pem" "$dir/"
        chmod 0644 "$dir/${pem##*/}"
        echo "$PROG: blocklisted ${pem##*/} in $dir"
    done < "$WORK/targets.lst"
    if [ "$KEEP_AAA" = "1" ]; then
        rm -f "$dir/AAA_Certificate_Services.pem"
    fi
}

apply_suse() {
    install_blocklist /etc/pki/trust/blacklist || return 1
    update-ca-certificates
}

apply_rhel() {
    install_blocklist /etc/pki/ca-trust/source/blocklist || return 1
    update-ca-trust
}

verify() {
    rc=0
    checked=0
    for b in /etc/ssl/certs/ca-certificates.crt \
             /etc/ssl/ca-bundle.pem \
             /var/lib/ca-certificates/ca-bundle.pem \
             /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
        [ -f "$b" ] || continue
        checked=1
        if bundle_trusts_target "$b"; then
            echo "$PROG: FAIL: $b still trusts a revoked root" >&2
            rc=1
        fi
    done
    if [ "$checked" = "0" ]; then
        echo "$PROG: warning: no system CA bundle found" >&2
    fi
    return $rc
}

if [ "$CHECK_ONLY" = "1" ]; then
    if verify; then
        echo "$PROG: OK, none of the revoked roots is trusted"
        exit 0
    fi
    exit 1
fi

family=$(detect_family)
echo "$PROG: trust store family: $family"
case $family in
    debian) apply_debian ;;
    suse) apply_suse ;;
    rhel) apply_rhel ;;
    *)
        if [ "${EMUDHRA_ALLOW_MISSING_STORE:-0}" = "1" ]; then
            echo "$PROG: warning: no trust store found, nothing to do (EMUDHRA_ALLOW_MISSING_STORE=1)" >&2
            exit 0
        fi
        echo "$PROG: unknown trust store layout, cannot apply the change" >&2
        exit 1
        ;;
esac

if verify; then
    echo "$PROG: OK, the revoked roots are removed from the system trust store"
else
    echo "$PROG: verification failed" >&2
    exit 1
fi
