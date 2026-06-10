#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_FIPS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Repo root is used as the build context so the Dockerfile can COPY hardware/udev rules.
REPO_ROOT="$(cd "${UBUNTU_FIPS_ROOT}/.." && pwd)"

BASE_IMAGE="${1:-ubuntu-noble-fips}"
VERSION=24.04
ENABLE_STIG="${ENABLE_STIG:-1}"
SKIP_STIG_BANNER="${SKIP_STIG_BANNER:-0}"

DOCKER_BUILDKIT=1 docker build \
  --secret id=pro-attach-config,src="${SCRIPT_DIR}/pro-attach-config.yaml" \
  --build-arg ENABLE_STIG="${ENABLE_STIG}" \
  --build-arg SKIP_STIG_BANNER="${SKIP_STIG_BANNER}" \
  -t "${BASE_IMAGE}" \
  -f "${SCRIPT_DIR}/Dockerfile.ubuntu${VERSION}-fips" \
  "${REPO_ROOT}"
