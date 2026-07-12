#!/usr/bin/env bash
#
# build_matrix.sh — emit the JSON matrix consumed by the build job in
# .github/workflows/base-images.yaml.
#
# Reads all inputs from IN_* / HAS_* env vars (set by the validate job).
# Writes the matrix to $GITHUB_OUTPUT under key "matrix" and a boolean
# "empty" flag so downstream `if:` can skip the build job cleanly.
#
# Rows:  {"family","os","version","variant","uki","fips","subscription"}
#
# Skip = row is not emitted. Never emit dead rows and then rely on `if:`
# inside the build job — that inflates the Actions UI and gives false
# "build ran" signals.
#
# Hard rules enforced here (fail fast, before any container starts):
#   1. If FIPS + UPDATE_KERNEL are both true, error out (Earthfile forbids it).
#   2. If a RHEL family is selected, require RHSM creds OR full Satellite set.
#   3. If Ubuntu FIPS is requested, require ubuntu_pro_token.
#   4. If SLEM is requested, require suse_registration_code.
#
# jq is preinstalled on ubuntu-latest.

set -euo pipefail

die() { echo "::error::$*" >&2; exit 1; }

is_true() { [ "${1:-false}" = "true" ]; }

# ── 1. Cross-input rules ────────────────────────────────────────────────
if is_true "$IN_VARIANT_FIPS" && is_true "$IN_UPDATE_KERNEL"; then
    die "variant_fips and update_kernel are mutually exclusive (Earthfile guard)."
fi

# ── 2. Determine credential availability ────────────────────────────────
has_rhsm="false"
if is_true "$HAS_RHSM_USER" && is_true "$HAS_RHSM_PASS"; then
    has_rhsm="true"
fi

has_satellite="false"
if is_true "$HAS_SAT_HOST" && is_true "$HAS_SAT_ORG" && is_true "$HAS_SAT_KEY"; then
    has_satellite="true"
fi

# Prefer RHSM if both provided (satellite is the fallback path).
rhel_subscription="none"
if is_true "$has_rhsm"; then
    rhel_subscription="rhsm"
elif is_true "$has_satellite"; then
    rhel_subscription="satellite"
fi

need_rhel="false"
if is_true "$IN_BUILD_RHEL8" || is_true "$IN_BUILD_RHEL9"; then
    need_rhel="true"
fi

if is_true "$need_rhel" && [ "$rhel_subscription" = "none" ]; then
    die "RHEL build requested but no RHSM (username+password) or Satellite (host+org+key) credentials provided."
fi

if is_true "$IN_BUILD_UBUNTU" && is_true "$IN_VARIANT_FIPS" && ! is_true "$HAS_UBUNTU_PRO"; then
    die "Ubuntu FIPS requested but ubuntu_pro_token is empty."
fi

if is_true "$IN_BUILD_SLEM" && ! is_true "$HAS_SUSE_REG"; then
    die "SLEM requested but suse_registration_code is empty."
fi

# ── 3. Build the matrix ─────────────────────────────────────────────────
rows="[]"
add_row() {
    local family="$1" os="$2" version="$3" variant="$4" uki="$5" fips="$6" subscription="${7:-}"
    rows="$(jq -c \
        --arg family "$family" --arg os "$os" --arg version "$version" \
        --arg variant "$variant" --argjson uki "$uki" --argjson fips "$fips" \
        --arg subscription "$subscription" \
        '. + [{family:$family, os:$os, version:$version, variant:$variant, uki:$uki, fips:$fips, subscription:$subscription}]' \
        <<<"$rows")"
}

# ── Ubuntu (Earthfile family + Ubuntu-FIPS family) ──────────────────────
if is_true "$IN_BUILD_UBUNTU"; then
    IFS=',' read -r -a ubuntu_versions <<<"${IN_UBUNTU_VERSIONS:-}"
    for raw in "${ubuntu_versions[@]}"; do
        v="${raw// /}"
        [ -z "$v" ] && continue
        case "$v" in
            20.04|22.04|24.04) ;;
            *) echo "::warning::Unknown Ubuntu version '$v' — skipping"; continue ;;
        esac

        if is_true "$IN_VARIANT_STANDARD"; then
            add_row "earthly" "ubuntu" "$v" "standard" false false
        fi
        if is_true "$IN_VARIANT_TRUSTED_BOOT"; then
            add_row "earthly" "ubuntu" "$v" "trusted-boot" true false
        fi
        if is_true "$IN_VARIANT_FIPS"; then
            add_row "ubuntu-fips" "ubuntu" "$v" "fips" false true
        fi
    done
fi

# ── OpenSUSE Leap ───────────────────────────────────────────────────────
if is_true "$IN_BUILD_OPENSUSE"; then
    # os_version.json currently pins to 15.6 — track that here.
    opensuse_version="15.6"
    if is_true "$IN_VARIANT_STANDARD"; then
        add_row "earthly" "opensuse-leap" "$opensuse_version" "standard" false false
    fi
    if is_true "$IN_VARIANT_TRUSTED_BOOT"; then
        add_row "earthly" "opensuse-leap" "$opensuse_version" "trusted-boot" true false
    fi
    # FIPS is not a supported OpenSUSE variant in this repo — silently drop.
fi

# ── RHEL 8 ──────────────────────────────────────────────────────────────
if is_true "$IN_BUILD_RHEL8"; then
    if is_true "$IN_VARIANT_STANDARD"; then
        add_row "rhel-core" "rhel" "8" "standard" false false "$rhel_subscription"
    fi
    if is_true "$IN_VARIANT_FIPS"; then
        # RHEL FIPS only supports the RHSM subscription path today
        # (no Dockerfile.rhel8.sat.fips exists).
        if [ "$rhel_subscription" = "rhsm" ]; then
            add_row "rhel-fips" "rhel" "8" "fips" false true "rhsm"
        else
            echo "::warning::RHEL 8 FIPS requires RHSM (username+password); Satellite path not supported yet. Skipping."
        fi
    fi
    if is_true "$IN_VARIANT_TRUSTED_BOOT"; then
        echo "::warning::RHEL 8 Trusted Boot is not implemented in this repo. Skipping."
    fi
fi

# ── RHEL 9 ──────────────────────────────────────────────────────────────
if is_true "$IN_BUILD_RHEL9"; then
    if is_true "$IN_VARIANT_STANDARD"; then
        add_row "rhel-core" "rhel" "9" "standard" false false "$rhel_subscription"
    fi
    if is_true "$IN_VARIANT_FIPS"; then
        if [ "$rhel_subscription" = "rhsm" ]; then
            add_row "rhel-fips" "rhel" "9" "fips" false true "rhsm"
        else
            echo "::warning::RHEL 9 FIPS requires RHSM (username+password); Satellite path not supported yet. Skipping."
        fi
    fi
    if is_true "$IN_VARIANT_TRUSTED_BOOT"; then
        echo "::warning::RHEL 9 Trusted Boot is not implemented in this repo. Skipping."
    fi
fi

# ── SLEM ────────────────────────────────────────────────────────────────
if is_true "$IN_BUILD_SLEM"; then
    # SLEM only has a "standard" build today. It also requires a self-hosted
    # SLE Micro runner (transactional-update on the host).
    add_row "slem" "sle-micro" "5.4" "standard" false false
fi

# ── 4. Emit ─────────────────────────────────────────────────────────────
count="$(jq 'length' <<<"$rows")"
empty="false"
if [ "$count" = "0" ]; then
    empty="true"
    echo "::warning::No matrix rows to build. Nothing was selected, or every selected variant was silently unsupported."
fi

matrix_json="$(jq -c '{include: .}' <<<"$rows")"

echo "Planned matrix ($count rows):"
jq . <<<"$matrix_json"

{
    echo "matrix=$matrix_json"
    echo "empty=$empty"
} >>"$GITHUB_OUTPUT"
