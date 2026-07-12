#!/usr/bin/env bash
#
# build-rhel-fips.sh — RHEL 8/9 FIPS build.
#
# Same credential concern as build-rhel-core.sh: the Dockerfile must be
# ported from ARG USERNAME/PASSWORD to BuildKit --mount=type=secret
# before this script can run.

set -euo pipefail

: "${MATRIX_VERSION:?}"
: "${CREDS_DIR:?}"
: "${PE_VERSION:?}"

image_tag="rhel${MATRIX_VERSION}-byoi-fips:${PE_VERSION}"
build_label="canvos.build=${MATRIX_OS}-${MATRIX_VERSION}"

export DOCKER_BUILDKIT=1

dockerfile="rhel-fips/Dockerfile.rhel${MATRIX_VERSION}"

if ! grep -q '\-\-mount=type=secret' "$dockerfile" 2>/dev/null; then
    cat >&2 <<EOF
::error::$dockerfile still uses ARG USERNAME/PASSWORD.
Port it to BuildKit --mount=type=secret,id=rhsm_username/rhsm_password
(mirror the pattern in rhel-stig/build.sh.rhel9). Blocking build to
prevent credentials from being baked into image layers.
EOF
    exit 1
fi

docker build \
    --secret id=rhsm_username,src="$CREDS_DIR/rhsm_username" \
    --secret id=rhsm_password,src="$CREDS_DIR/rhsm_password" \
    --label "$build_label" \
    -t "$image_tag" \
    -f "$dockerfile" \
    rhel-fips/

mkdir -p build
docker save "$image_tag" | gzip > "build/rhel${MATRIX_VERSION}-fips.tar.gz"
