#!/usr/bin/env bash
#
# build-ubuntu-fips.sh — Ubuntu 20.04 / 22.04 / 24.04 FIPS build.
#
# Wraps the per-version ubuntu-fips/<v>/build.sh pattern (BuildKit
# `--secret id=pro-attach-config,src=…`), but points the secret at a
# pro-attach-config.yaml rendered on the fly by materialize_credentials.sh
# from the workflow's UBUNTU_PRO_TOKEN input — never the committed
# template with "REPLACE_WITH_TOKEN".

set -euo pipefail

: "${MATRIX_VERSION:?}"   # 20.04 / 22.04 / 24.04
: "${CREDS_DIR:?}"
: "${PE_VERSION:?}"

version="$MATRIX_VERSION"
case "$version" in
    20.04) codename="focal" ;;
    22.04) codename="jammy" ;;
    24.04) codename="noble" ;;
    *) echo "::error::Unsupported Ubuntu FIPS version: $version"; exit 1 ;;
esac

image_tag="ubuntu-${codename}-fips:${PE_VERSION}"
build_label="canvos.build=${MATRIX_OS}-${MATRIX_VERSION}"

export DOCKER_BUILDKIT=1

# 20.04 has "Dockerfile" with its own build context; 22.04 and 24.04 use
# Dockerfile.ubuntu<version>-fips with the parent ubuntu-fips/ as context.
case "$version" in
    20.04)
        dockerfile="ubuntu-fips/20.04/Dockerfile"
        build_context="ubuntu-fips/20.04"
        ;;
    22.04|24.04)
        dockerfile="ubuntu-fips/${version}/Dockerfile.ubuntu${version}-fips"
        build_context="ubuntu-fips"
        ;;
esac

docker build \
    --secret id=pro-attach-config,src="$CREDS_DIR/pro-attach-config.yaml" \
    --label "$build_label" \
    -t "$image_tag" \
    -f "$dockerfile" \
    "$build_context"

mkdir -p build
docker save "$image_tag" | gzip > "build/ubuntu-${codename}-fips.tar.gz"
