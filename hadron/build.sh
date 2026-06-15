#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


ADDITIONAL_PACKAGES_IMAGE="${1:-us-east1-docker.pkg.dev/spectro-images/dev/arun/hadron/additional-packages:v0.3.3-rc2}"


DOCKER_BUILDKIT=1 docker build \
  --progress=plain --no-cache \
  -t "${ADDITIONAL_PACKAGES_IMAGE}" \
  -f "${SCRIPT_DIR}/Dockerfile.extras" \
  --load \
  . 

echo "Built ${ADDITIONAL_PACKAGES_IMAGE}"
