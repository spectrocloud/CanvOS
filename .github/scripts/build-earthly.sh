#!/usr/bin/env bash
#
# build-earthly.sh — Earthfile-based build for Ubuntu (non-FIPS), OpenSUSE
# Leap, and Trusted Boot / UKI variants. Delegates to +iso in the repo
# Earthfile.

set -euo pipefail

: "${MATRIX_OS:?}"
: "${MATRIX_VERSION:?}"
: "${ARCH:?}"
: "${PE_VERSION:?}"
: "${K8S_DISTRIBUTION:?}"

# Earthfile treats Ubuntu OS_VERSION as the major-only (22, 24) except when
# it isn't — see Earthfile lines 108-116. Match that: strip ".04" for Ubuntu,
# keep as-is for opensuse-leap.
os_version="$MATRIX_VERSION"
if [ "$MATRIX_OS" = "ubuntu" ]; then
    os_version="${MATRIX_VERSION%%.*}"
fi

./earthly --ci -P \
    "--PE_VERSION=$PE_VERSION" \
    "--OS_DISTRIBUTION=$MATRIX_OS" \
    "--OS_VERSION=$os_version" \
    "--K8S_DISTRIBUTION=$K8S_DISTRIBUTION" \
    "--ARCH=$ARCH" \
    "--IS_UKI=${MATRIX_UKI:-false}" \
    "--FIPS_ENABLED=${MATRIX_FIPS:-false}" \
    "+iso"

mkdir -p build
[ -d ./build ] && ls -la ./build || true
