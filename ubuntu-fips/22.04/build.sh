#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_FIPS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Mozilla bug 2083449: provide the distrust script in the build context.
cp "${UBUNTU_FIPS_ROOT}/../scripts/distrust-emudhra-roots.sh" "${UBUNTU_FIPS_ROOT}/"
trap 'rm -f "${UBUNTU_FIPS_ROOT}/distrust-emudhra-roots.sh"' EXIT

BASE_IMAGE="${1:-ubuntu-jammy-fips}"
VERSION=22.04
ENABLE_STIG="${ENABLE_STIG:-1}"
SKIP_STIG_BANNER="${SKIP_STIG_BANNER:-0}"

DOCKER_BUILDKIT=1 docker build \
  --secret id=pro-attach-config,src="${SCRIPT_DIR}/pro-attach-config.yaml" \
  --build-arg ENABLE_STIG="${ENABLE_STIG}" \
  --build-arg SKIP_STIG_BANNER="${SKIP_STIG_BANNER}" \
  -t "${BASE_IMAGE}" \
  -f "${SCRIPT_DIR}/Dockerfile.ubuntu${VERSION}-fips" \
  "${UBUNTU_FIPS_ROOT}"
