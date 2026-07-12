#!/usr/bin/env bash
#
# build-rhel-core.sh — RHEL 8/9 non-FIPS build.
#
# IMPORTANT: The current Dockerfiles in rhel-core-images/ take USERNAME and
# PASSWORD as `ARG` (`--build-arg`). That bakes credentials into the image
# layers and leaves them visible in `docker history`. This script uses
# BuildKit `--secret` so credentials do NOT enter layers — but the
# Dockerfiles must be ported to read from /run/secrets/... first. The port
# is a separate commit on this branch. Until then, this script errors out
# for RHSM-mode builds.
#
# The Satellite path (Dockerfile.rhel{8,9}.sat) takes activation-key inputs
# as `ARG` too and needs the same port.

set -euo pipefail

: "${MATRIX_VERSION:?}"       # "8" or "9"
: "${CREDS_DIR:?}"
: "${RHEL_SUBSCRIPTION:?}"    # "rhsm" or "satellite"
: "${PE_VERSION:?}"

image_tag="${IMAGE_REGISTRY:+$IMAGE_REGISTRY/}rhel${MATRIX_VERSION}-byoi:${PE_VERSION}${CUSTOM_TAG:+-$CUSTOM_TAG}"
build_label="canvos.build=${MATRIX_OS}-${MATRIX_VERSION}"

export DOCKER_BUILDKIT=1

case "$RHEL_SUBSCRIPTION" in
    rhsm)
        dockerfile="rhel-core-images/Dockerfile.rhel${MATRIX_VERSION}"
        # Sanity: fail loudly if the Dockerfile still uses ARG USERNAME/PASSWORD
        # instead of BuildKit --mount=type=secret. The port lands in a
        # separate commit on this branch.
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
        ;;

    satellite)
        dockerfile="rhel-core-images/Dockerfile.rhel${MATRIX_VERSION}.sat"
        if ! grep -q '\-\-mount=type=secret' "$dockerfile" 2>/dev/null; then
            cat >&2 <<EOF
::error::$dockerfile still uses ARG for Satellite creds.
Port it to BuildKit --mount=type=secret before this script can build.
EOF
            exit 1
        fi
        # The BASE_IMAGE and KAIROS_FRAMEWORK_IMAGE fields are not secrets;
        # they are container image paths and can safely be --build-arg.
        docker build \
            --secret id=satellite_hostname,src="$CREDS_DIR/satellite_hostname" \
            --secret id=satellite_org,src="$CREDS_DIR/satellite_org" \
            --secret id=satellite_key,src="$CREDS_DIR/satellite_key" \
            ${RHEL_BASE_IMAGE:+--build-arg BASE_IMAGE="$RHEL_BASE_IMAGE"} \
            ${RHEL_KAIROS_FRAMEWORK_IMAGE:+--build-arg KAIROS_FRAMEWORK_IMAGE="$RHEL_KAIROS_FRAMEWORK_IMAGE"} \
            --label "$build_label" \
            -t "$image_tag" \
            -f "$dockerfile" \
            rhel-core-images/
        ;;

    *)
        echo "::error::Unknown RHEL_SUBSCRIPTION: $RHEL_SUBSCRIPTION"
        exit 1
        ;;
esac

# Save the image for the artifact upload step.
mkdir -p build
docker save "$image_tag" | gzip > "build/rhel${MATRIX_VERSION}-${RHEL_SUBSCRIPTION}.tar.gz"

if [ -n "${IMAGE_REGISTRY:-}" ]; then
    docker push "$image_tag"
fi
