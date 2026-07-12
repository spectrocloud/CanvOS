#!/usr/bin/env bash
#
# build_matrix.sh — emit the JSON matrix consumed by the build job in
# .github/workflows/base-images.yaml.
#
# By default the matrix covers every OS the release ships. Two checkboxes
# (IN_TRUSTED_BOOT, IN_FIPS) expand the set. Credentials are what gate
# which families make it in:
#
#   - Ubuntu 20/22 standard, OpenSUSE 15.6 standard  → always in
#   - Ubuntu 20/22 trusted-boot, OpenSUSE trusted-boot → in iff IN_TRUSTED_BOOT
#   - Ubuntu 20/22/24 FIPS                            → in iff IN_FIPS  (needs Ubuntu Pro token)
#   - RHEL 8/9 standard                               → in iff RHSM creds
#   - RHEL 8/9 FIPS                                   → in iff IN_FIPS AND RHSM creds
#   - SLE Micro                                       → in iff SUSE reg code
#
# Hard error only when the user explicitly asked for something and the
# required credential is missing (e.g. fips=true but no Ubuntu Pro token).
# Everything else is a soft skip with a ::warning:: line.

set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }
is_true() { [ "${1:-false}" = "true" ]; }

# ── Which credentials are available ────────────────────────────────────
has_rhsm="false"
if is_true "$HAS_RHSM_USER" && is_true "$HAS_RHSM_PASS"; then
    has_rhsm="true"
fi

# ── Cross-input rules ──────────────────────────────────────────────────
if is_true "$IN_FIPS" && ! is_true "$HAS_UBUNTU_PRO"; then
    die "fips=true but ubuntu_pro_token is empty — Ubuntu FIPS needs it."
fi

# ── Matrix constants ───────────────────────────────────────────────────
UBUNTU_STANDARD_VERSIONS=("20.04" "22.04")     # from os_version.json
UBUNTU_FIPS_VERSIONS=("20.04" "22.04" "24.04") # from ubuntu-fips/*/
OPENSUSE_VERSION="15.6"
SLEM_VERSION="5.4"

# ── Build the matrix ───────────────────────────────────────────────────
rows="[]"
add_row() {
    local family="$1" os="$2" version="$3" variant="$4" uki="$5" fips="$6"
    rows="$(jq -c \
        --arg family "$family" --arg os "$os" --arg version "$version" \
        --arg variant "$variant" --argjson uki "$uki" --argjson fips "$fips" \
        '. + [{family:$family, os:$os, version:$version, variant:$variant, uki:$uki, fips:$fips}]' \
        <<<"$rows")"
}

# Ubuntu standard (always)
for v in "${UBUNTU_STANDARD_VERSIONS[@]}"; do
    add_row "earthly" "ubuntu" "$v" "standard" false false
done

# Ubuntu trusted-boot
if is_true "$IN_TRUSTED_BOOT"; then
    for v in "${UBUNTU_STANDARD_VERSIONS[@]}"; do
        add_row "earthly" "ubuntu" "$v" "trusted-boot" true false
    done
fi

# Ubuntu FIPS
if is_true "$IN_FIPS"; then
    for v in "${UBUNTU_FIPS_VERSIONS[@]}"; do
        add_row "ubuntu-fips" "ubuntu" "$v" "fips" false true
    done
fi

# OpenSUSE standard (always)
add_row "earthly" "opensuse-leap" "$OPENSUSE_VERSION" "standard" false false

# OpenSUSE trusted-boot
if is_true "$IN_TRUSTED_BOOT"; then
    add_row "earthly" "opensuse-leap" "$OPENSUSE_VERSION" "trusted-boot" true false
fi

# RHEL 8/9 standard — needs RHSM
if is_true "$has_rhsm"; then
    add_row "rhel-core" "rhel" "8" "standard" false false
    add_row "rhel-core" "rhel" "9" "standard" false false
else
    echo "::warning::rhel_subscription_username/password blank — skipping RHEL 8/9 builds."
fi

# RHEL 8/9 FIPS — needs RHSM AND fips checkbox
if is_true "$IN_FIPS"; then
    if is_true "$has_rhsm"; then
        add_row "rhel-fips" "rhel" "8" "fips" false true
        add_row "rhel-fips" "rhel" "9" "fips" false true
    else
        echo "::warning::fips=true but no RHSM creds — skipping RHEL 8/9 FIPS builds."
    fi
fi

# SLEM — needs reg code
if is_true "$HAS_SUSE_REG"; then
    add_row "slem" "sle-micro" "$SLEM_VERSION" "standard" false false
else
    echo "::warning::suse_registration_code blank — skipping SLEM build."
fi

# ── Emit ───────────────────────────────────────────────────────────────
count="$(jq 'length' <<<"$rows")"
empty="false"
if [ "$count" = "0" ]; then
    empty="true"
    echo "::warning::No matrix rows to build."
fi

matrix_json="$(jq -c '{include: .}' <<<"$rows")"

echo "Planned matrix ($count rows):"
jq . <<<"$matrix_json"

{
    echo "matrix=$matrix_json"
    echo "empty=$empty"
} >>"$GITHUB_OUTPUT"
