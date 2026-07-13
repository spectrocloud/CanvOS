#!/usr/bin/env bash
#
# build-extension.sh — one dispatcher for RHEL and Ubuntu FIPS builds.
#
# Matrix inputs (from workflow env):
#   MATRIX_FAMILY     rhel-core | rhel-fips | ubuntu-fips
#   MATRIX_VERSION    8/9 (rhel) or 20.04/22.04 (ubuntu-fips)
#   MATRIX_TAG        full registry tag to push
#   MATRIX_DOCKERFILE path to the Dockerfile
#   MATRIX_CONTEXT    build context dir
#   CREDS_DIR         where materialize_credentials.sh wrote secret files
#
# All families use BuildKit --secret so credentials never enter image layers.

set -euo pipefail

: "${MATRIX_FAMILY:?}"
: "${MATRIX_TAG:?}"
: "${MATRIX_DOCKERFILE:?}"
: "${MATRIX_CONTEXT:?}"
: "${CREDS_DIR:?}"

export DOCKER_BUILDKIT=1

# Sanity: the Dockerfile must use BuildKit --mount=type=secret. If we ever
# regressed the RHEL Dockerfile port, refuse to build rather than bake
# credentials into image layers via --build-arg.
if [[ "$MATRIX_FAMILY" == rhel-* ]]; then
    if ! grep -q 'mount=type=secret,id=rhsm' "$MATRIX_DOCKERFILE"; then
        echo "::error::$MATRIX_DOCKERFILE does not use --mount=type=secret,id=rhsm_username/rhsm_password"
        exit 1
    fi
fi

echo "→ Building $MATRIX_TAG from $MATRIX_DOCKERFILE (context: $MATRIX_CONTEXT)"

case "$MATRIX_FAMILY" in
    rhel-core|rhel-fips)
        docker build \
            --secret id=rhsm_username,src="$CREDS_DIR/rhsm_username" \
            --secret id=rhsm_password,src="$CREDS_DIR/rhsm_password" \
            --label "canvos.build=${MATRIX_FAMILY}-${MATRIX_VERSION}" \
            -t "$MATRIX_TAG" \
            -f "$MATRIX_DOCKERFILE" \
            "$MATRIX_CONTEXT"
        ;;

    ubuntu-fips)
        docker build \
            --secret id=pro-attach-config,src="$CREDS_DIR/pro-attach-config.yaml" \
            --label "canvos.build=${MATRIX_FAMILY}-${MATRIX_VERSION}" \
            -t "$MATRIX_TAG" \
            -f "$MATRIX_DOCKERFILE" \
            "$MATRIX_CONTEXT"
        ;;

    *)
        echo "::error::Unknown MATRIX_FAMILY: $MATRIX_FAMILY"
        exit 1
        ;;
esac

echo "→ Pushing $MATRIX_TAG"
docker push "$MATRIX_TAG"
