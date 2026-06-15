#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KAIROS_VERSION=v4.1.0
IMAGE="${1:-us-east1-docker.pkg.dev/spectro-images/dev/arun/base/hadron-fips-v0.3.5:${KAIROS_VERSION}}"

DOCKER_BUILDKIT=1 docker build \
  --progress=plain \
  --build-arg KAIROS_VERSION="${KAIROS_VERSION}" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  -t "${IMAGE}" \
  --push \
  "${SCRIPT_DIR}"

echo "Built ${IMAGE}"
