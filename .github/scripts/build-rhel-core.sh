#!/usr/bin/env bash
#
# build-rhel-core.sh — RHEL 8/9 non-FIPS build.
#
# IMPORTANT: rhel-core-images/Dockerfile.rhel{8,9} currently take
# USERNAME/PASSWORD as `ARG` (--build-arg). That bakes credentials into
# the image layers and leaves them visible in `docker history`. This
# script uses BuildKit `--secret` so credentials do NOT enter layers —
# but the Dockerfiles must be ported to read from /run/secrets/... first.
# The port is a separate commit on this branch. Until then, this script
# errors out.

set -euo pipefail

: "${MATRIX_VERSION:?}"   # "8" or "9"
: "${CREDS_DIR:?}"
: "${PE_VERSION:?}"

image_tag="rhel${MATRIX_VERSION}-byoi:${PE_VERSION}"
build_label="canvos.build=${MATRIX_OS}-${MATRIX_VERSION}"

export DOCKER_BUILDKIT=1

dockerfile="rhel-core-images/Dockerfile.rhel${MATRIX_VERSION}"

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
    rhel-core-images/

mkdir -p build
docker save "$image_tag" | gzip > "build/rhel${MATRIX_VERSION}.tar.gz"
