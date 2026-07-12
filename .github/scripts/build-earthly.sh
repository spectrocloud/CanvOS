#!/usr/bin/env bash
#
# build-earthly.sh — Earthfile-based build for Ubuntu (non-FIPS), OpenSUSE
# Leap, and Trusted Boot / UKI variants. Delegates to +iso-image /
# +build-provider-images in the repo Earthfile.
#
# Consumes env from base-images.yaml's build job:
#   MATRIX_OS, MATRIX_VERSION, MATRIX_VARIANT, MATRIX_UKI, MATRIX_FIPS
#   PE_VERSION, KAIROS_VERSION, CUSTOM_TAG, IMAGE_REGISTRY, ARCH
#   K8S_DISTRIBUTION, CIS_HARDENING, IS_MAAS, UPDATE_KERNEL, UBUNTU_PRO_KEY

set -euo pipefail

: "${MATRIX_OS:?}"
: "${MATRIX_VERSION:?}"
: "${ARCH:?}"
: "${PE_VERSION:?}"
: "${K8S_DISTRIBUTION:?}"

# Ubuntu OS_VERSION on the Earthfile is the MAJOR only (22, 24) except when
# it isn't — see Earthfile lines 108-116. We mirror that convention: strip
# the ".04" for Ubuntu, keep as-is for opensuse-leap.
os_version="$MATRIX_VERSION"
if [ "$MATRIX_OS" = "ubuntu" ]; then
    os_version="${MATRIX_VERSION%%.*}"
fi

args=(
    --ci
    -P
    "--PE_VERSION=$PE_VERSION"
    "--OS_DISTRIBUTION=$MATRIX_OS"
    "--OS_VERSION=$os_version"
    "--K8S_DISTRIBUTION=$K8S_DISTRIBUTION"
    "--ARCH=$ARCH"
    "--IS_UKI=${MATRIX_UKI:-false}"
    "--FIPS_ENABLED=${MATRIX_FIPS:-false}"
    "--IS_MAAS=${IS_MAAS:-false}"
    "--CIS_HARDENING=${CIS_HARDENING:-false}"
    "--UPDATE_KERNEL=${UPDATE_KERNEL:-false}"
)

[ -n "${KAIROS_VERSION:-}" ] && args+=("--KAIROS_VERSION=$KAIROS_VERSION")
[ -n "${CUSTOM_TAG:-}" ]     && args+=("--CUSTOM_TAG=$CUSTOM_TAG")
[ -n "${IMAGE_REGISTRY:-}" ] && args+=("--IMAGE_REGISTRY=$IMAGE_REGISTRY")
[ -n "${UBUNTU_PRO_KEY:-}" ] && args+=("--UBUNTU_PRO_KEY=$UBUNTU_PRO_KEY")

# Choose target. For a full ISO + provider image build, use +iso. Providers
# also come along for free in +build-all-images. Sticking with +iso here to
# match what the manual release process produces.
target="+iso"
if [ -n "${IMAGE_REGISTRY:-}" ]; then
    args=(--push "${args[@]}")
fi

echo "→ ./earthly ${args[*]} $target"
./earthly "${args[@]}" "$target"

# Copy artifacts into a per-variant subdir so upload-artifact can pick them
# up unambiguously across the whole matrix.
mkdir -p "build"
[ -d ./build ] && ls -la ./build || true
