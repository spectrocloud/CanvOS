#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTPUT=load
NO_CACHE=false
KEEP_GPU_FIRMWARE="${KEEP_GPU_FIRMWARE:-false}"
KAIROS_VERSION="${KAIROS_VERSION:-v4.1.2}"
KAIROS_INIT_VERSION="${KAIROS_INIT_VERSION:-v0.17.1}"
KAIROS_INIT_IMAGE="${KAIROS_INIT_IMAGE:-quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION}}"
SPECTRO_REPO="${SPECTRO_REPO:-us-east1-docker.pkg.dev/spectro-images/dev/arun}"
ARCH="${ARCH:-amd64}"
IMAGE_TAG=""

usage() {
  cat <<'EOF'
Usage: build.sh [OPTIONS]

Build the Ubuntu 24.04 Kairos Trusted Boot (UKI) base image with AMD/NVIDIA
GPU firmware trimmed by default (LP#1958518 workaround).

Options:
  --tag NAME              Image tag to build (default:
                          ${SPECTRO_REPO}/kairos-ubuntu:24.04-core-${ARCH}-generic-${KAIROS_INIT_VERSION}-uki)
  --arch {amd64|arm64}    Target architecture (default: amd64)
  --keep-gpu-firmware     Keep full linux-firmware GPU blobs (larger UKI)
  --push                  Push the image. Default: --load
  --no-cache              Pass --no-cache to docker buildx build
  -h, --help              Show this help

Environment (CLI flags win):
  ARCH                    Target architecture (default amd64)
  KEEP_GPU_FIRMWARE       true|false (default false)
  KAIROS_VERSION          Passed to kairos-init --version (default v4.1.2)
  KAIROS_INIT_VERSION     Default output tag component (v0.17.1)
  KAIROS_INIT_IMAGE       Complete kairos-init image reference
  SPECTRO_REPO            Registry/org prefix for the default tag

Examples:
  ./build.sh
  ./build.sh --arch arm64 --push
  ./build.sh --tag myregistry/ubuntu-uki:24.04 --push
  KEEP_GPU_FIRMWARE=true ./build.sh --tag myregistry/ubuntu-uki:24.04-fullgpu

Then point CanvOS at the image:
  BASE_IMAGE=<tag>
  OS_DISTRIBUTION=ubuntu
  OS_VERSION=24.04
  IS_UKI=true
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -gt 1 ]] || { echo "--tag requires an argument" >&2; usage 1; }
      IMAGE_TAG="$2"; shift 2 ;;
    --arch)
      [[ $# -gt 1 ]] || { echo "--arch requires an argument" >&2; usage 1; }
      ARCH="$2"; shift 2 ;;
    --keep-gpu-firmware) KEEP_GPU_FIRMWARE=true; shift ;;
    --push)              OUTPUT=push; shift ;;
    --no-cache)          NO_CACHE=true; shift ;;
    -h|--help)           usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "Error: docker not found on PATH" >&2; exit 1; }

case "${ARCH}" in
  amd64|arm64) ;;
  *) echo "Unsupported architecture: ${ARCH} (expected amd64 or arm64)" >&2; exit 1 ;;
esac

IMAGE_TAG="${IMAGE_TAG:-${SPECTRO_REPO}/kairos-ubuntu:24.04-core-${ARCH}-generic-${KAIROS_INIT_VERSION}-uki}"
PLATFORM="linux/${ARCH}"

CACHE_ARGS=()
if [ "${NO_CACHE}" = "true" ]; then
  CACHE_ARGS=(--no-cache)
fi

echo "Build configuration:"
echo "  Image tag:           ${IMAGE_TAG}"
echo "  Architecture:        ${ARCH}"
echo "  Kairos version:      ${KAIROS_VERSION}"
echo "  kairos-init version: ${KAIROS_INIT_VERSION}"
echo "  kairos-init image:   ${KAIROS_INIT_IMAGE}"
echo "  KEEP_GPU_FIRMWARE:   ${KEEP_GPU_FIRMWARE}"
echo "  Platform:            ${PLATFORM}"
echo "  Output:              ${OUTPUT}"

docker buildx build \
  --progress=plain \
  --platform "${PLATFORM}" \
  "${CACHE_ARGS[@]}" \
  --build-arg VERSION="${KAIROS_VERSION}" \
  --build-arg KAIROS_INIT_VERSION="${KAIROS_INIT_VERSION}" \
  --build-arg KAIROS_INIT_IMAGE="${KAIROS_INIT_IMAGE}" \
  --build-arg KEEP_GPU_FIRMWARE="${KEEP_GPU_FIRMWARE}" \
  --build-arg MODEL=generic \
  -f "${SCRIPT_DIR}/Dockerfile" \
  -t "${IMAGE_TAG}" \
  "--${OUTPUT}" \
  "${SCRIPT_DIR}"

echo
echo "Built ${IMAGE_TAG}"
echo "Use in .arg:"
echo "  BASE_IMAGE=${IMAGE_TAG}"
echo "  OS_DISTRIBUTION=ubuntu"
echo "  OS_VERSION=24.04"
echo "  IS_UKI=true"
