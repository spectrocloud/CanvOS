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

# Trusted Boot / UKI builds require Secure Boot signing keys under
# ./secure-boot/{enrollment,private-keys,public-keys}. Those aren't
# committed (they're private keys). The Earthfile provides `+uki-genkey`
# to generate them locally. If the dirs are missing, generate fresh
# per-run keys — fine for CI test-builds; a real release must supply
# stable pre-generated keys (e.g., extracted from a repo secret before
# this script runs) so Secure Boot enrollment doesn't need to be redone
# every release.
if [ "${MATRIX_UKI:-false}" = "true" ] && [ ! -d ./secure-boot/enrollment ]; then
    echo "→ UKI build: generating ephemeral Secure Boot keys (CI-only; not for a real release)"
    earthly --ci -P +uki-genkey --MY_ORG="Palette CI"
fi

# Earthly syntax: `earthly [OPTIONS] +TARGET [--BUILD_ARG=VALUE ...]`
# Build args go AFTER the target; before, they're parsed as global options
# and earthly prints help + exits 1 on the unknown flag.
earthly --ci -P +iso \
    "--PE_VERSION=$PE_VERSION" \
    "--OS_DISTRIBUTION=$MATRIX_OS" \
    "--OS_VERSION=$os_version" \
    "--K8S_DISTRIBUTION=$K8S_DISTRIBUTION" \
    "--ARCH=$ARCH" \
    "--IS_UKI=${MATRIX_UKI:-false}" \
    "--FIPS_ENABLED=${MATRIX_FIPS:-false}"

mkdir -p build
[ -d ./build ] && ls -la ./build || true
