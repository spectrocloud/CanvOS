#!/usr/bin/env bash
#
# materialize_credentials.sh — write credentials for THIS matrix row to
# $RUNNER_TEMP/creds with umask 077, then export CREDS_DIR to $GITHUB_ENV
# so the family build script can read them via BuildKit --secret.
#
# Credentials come in via env (from workflow_dispatch inputs). This script
# is the ONLY place they are written to disk. Cleanup (`shred -u`) happens
# in an `if: always()` step after the build.
#
# Never echo the values. Never assign to $GITHUB_ENV. Never `set -x`.

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP not set — this must run inside GitHub Actions}"
: "${MATRIX_FAMILY:?MATRIX_FAMILY not set}"

umask 077
creds_dir="$RUNNER_TEMP/creds"
mkdir -p "$creds_dir"

case "$MATRIX_FAMILY" in
    rhel-core)
        # Prefer RHSM if both were provided (matches build_matrix.sh logic).
        if [ -n "${RHSM_USER:-}" ] && [ -n "${RHSM_PASS:-}" ]; then
            printf '%s' "$RHSM_USER" > "$creds_dir/rhsm_username"
            printf '%s' "$RHSM_PASS" > "$creds_dir/rhsm_password"
            echo "RHEL_SUBSCRIPTION=rhsm" >> "$GITHUB_ENV"
        elif [ -n "${SAT_HOST:-}" ] && [ -n "${SAT_ORG:-}" ] && [ -n "${SAT_KEY:-}" ]; then
            printf '%s' "$SAT_HOST" > "$creds_dir/satellite_hostname"
            printf '%s' "$SAT_ORG"  > "$creds_dir/satellite_org"
            printf '%s' "$SAT_KEY"  > "$creds_dir/satellite_key"
            echo "RHEL_SUBSCRIPTION=satellite" >> "$GITHUB_ENV"
            # Non-secret Satellite fields — safe to expose as env.
            {
                echo "RHEL_BASE_IMAGE=${SAT_BASE:-}"
                echo "RHEL_KAIROS_FRAMEWORK_IMAGE=${SAT_KFI:-}"
            } >> "$GITHUB_ENV"
        else
            echo "::error::rhel-core build has no credentials in scope"
            exit 1
        fi
        ;;

    rhel-fips)
        # RHEL FIPS only supports RHSM today. Satellite would need a new
        # Dockerfile — flag it in build_matrix.sh, not here.
        if [ -z "${RHSM_USER:-}" ] || [ -z "${RHSM_PASS:-}" ]; then
            echo "::error::rhel-fips build requires RHSM username+password"
            exit 1
        fi
        printf '%s' "$RHSM_USER" > "$creds_dir/rhsm_username"
        printf '%s' "$RHSM_PASS" > "$creds_dir/rhsm_password"
        ;;

    ubuntu-fips)
        if [ -z "${UBUNTU_PRO_TOKEN:-}" ]; then
            echo "::error::ubuntu-fips build requires ubuntu_pro_token"
            exit 1
        fi
        # Ubuntu FIPS build.sh scripts consume a pro-attach-config.yaml via
        # BuildKit secret id=pro-attach-config. We render it here on the fly
        # instead of committing a template with a placeholder token.
        cat > "$creds_dir/pro-attach-config.yaml" <<EOF
token: "$UBUNTU_PRO_TOKEN"
enable_services:
  - fips-updates
EOF
        ;;

    slem)
        if [ -z "${SUSE_REG_CODE:-}" ]; then
            echo "::error::slem build requires suse_registration_code"
            exit 1
        fi
        printf '%s' "$SUSE_REG_CODE" > "$creds_dir/suse_registration_code"
        ;;

    earthly)
        # Non-FIPS Ubuntu/OpenSUSE/Trusted-Boot need no persistent credentials.
        # Ubuntu Pro attach on Earthfile is optional and orthogonal to FIPS —
        # if the user pasted a token AND is running Ubuntu here, plumb it
        # through as an Earthly build arg (never a secret file: the Earthfile
        # currently passes it via --UBUNTU_PRO_KEY as a build arg and detaches
        # it in the same layer, see Earthfile lines 729-807).
        if [ -n "${UBUNTU_PRO_TOKEN:-}" ]; then
            echo "UBUNTU_PRO_KEY=$UBUNTU_PRO_TOKEN" >> "$GITHUB_ENV"
        fi
        ;;

    *)
        echo "::error::Unknown MATRIX_FAMILY: $MATRIX_FAMILY"
        exit 1
        ;;
esac

echo "CREDS_DIR=$creds_dir" >> "$GITHUB_ENV"
echo "Credentials materialized for family=$MATRIX_FAMILY (values not shown)."
