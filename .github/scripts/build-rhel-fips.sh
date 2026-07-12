#!/usr/bin/env bash
#
# build-rhel-fips.sh — RHEL 8/9 FIPS build.
#
# Uses rhel-fips/Dockerfile.rhel{8,9}. Same credential concern as
# build-rhel-core.sh: the Dockerfile must have been ported to BuildKit
# --mount=type=secret before this script can run. The port is a separate
# commit on this branch.

set -euo pipefail

: "${MATRIX_VERSION:?}"
: "${CREDS_DIR:?}"
: "${PE_VERSION:?}"

image_tag="${IMAGE_REGISTRY:+$IMAGE_REGISTRY/}rhel${MATRIX_VERSION}-byoi-fips:${PE_VERSION}${CUSTOM_TAG:+-$CUSTOM_TAG}"
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

if [ -n "${IMAGE_REGISTRY:-}" ]; then
    docker push "$image_tag"
fi
