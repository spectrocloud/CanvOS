#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${1:-us-east1-docker.pkg.dev/spectro-images/dev/arun/base/hadron-modules:v4.1.0}"

DOCKER_BUILDKIT=1 docker build \
  --progress=plain \
  -f "${SCRIPT_DIR}/Dockerfile" \
  -t "${IMAGE}" \
  --push \
  "${SCRIPT_DIR}"

echo "Built ${IMAGE}"
