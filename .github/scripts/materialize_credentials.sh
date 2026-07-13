#!/usr/bin/env bash
#
# materialize_credentials.sh — write credentials for THIS extensions-matrix
# row to $RUNNER_TEMP/creds with umask 077, then export CREDS_DIR to
# $GITHUB_ENV so build-extension.sh can pass them via BuildKit --secret.
#
# Never echo the values. Never assign values to $GITHUB_ENV. No `set -x`.

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP not set — this must run inside GitHub Actions}"
: "${MATRIX_FAMILY:?MATRIX_FAMILY not set}"

umask 077
creds_dir="$RUNNER_TEMP/creds"
mkdir -p "$creds_dir"

case "$MATRIX_FAMILY" in
    rhel-core|rhel-fips)
        if [ -z "${RHSM_USER:-}" ] || [ -z "${RHSM_PASS:-}" ]; then
            echo "::error::$MATRIX_FAMILY build requires RHSM username+password"
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
        # Render pro-attach-config.yaml on the fly. The committed template
        # in ubuntu-fips/*/pro-attach-config.yaml has "REPLACE_WITH_TOKEN"
        # and must not be used.
        cat > "$creds_dir/pro-attach-config.yaml" <<EOF
token: "$UBUNTU_PRO_TOKEN"
enable_services:
  - fips-updates
EOF
        ;;

    *)
        echo "::error::Unknown MATRIX_FAMILY: $MATRIX_FAMILY"
        exit 1
        ;;
esac

echo "CREDS_DIR=$creds_dir" >> "$GITHUB_ENV"
echo "Credentials materialized for family=$MATRIX_FAMILY (values not shown)."
