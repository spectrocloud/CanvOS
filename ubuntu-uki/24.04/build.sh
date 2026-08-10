#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTPUT=load
NO_CACHE=false
KEEP_GPU_FIRMWARE="${KEEP_GPU_FIRMWARE:-false}"
KAIROS_VERSION="${KAIROS_VERSION:-v4.1.2}"
KAIROS_INIT_VERSION="${KAIROS_INIT_VERSION:-v0.16.2}"
SPECTRO_REPO="${SPECTRO_REPO:-us-east1-docker.pkg.dev/spectro-images/dev/arun}"
IMAGE_TAG=""

usage() {
  cat <<'EOF'
Usage: build.sh [OPTIONS]

Build the Ubuntu 24.04 Kairos Trusted Boot (UKI) base image with AMD/NVIDIA
GPU firmware trimmed by default (LP#1958518 workaround).

Options:
  --tag NAME              Image tag to build (default:
                          ${SPECTRO_REPO}/base/ubuntu-uki-24.04:${KAIROS_INIT_VERSION})
  --keep-gpu-firmware     Keep full linux-firmware GPU blobs (larger UKI)
  --push                  Push the image (multi-arch amd64+arm64). Default: --load
  --no-cache              Pass --no-cache to docker buildx build
  -h, --help              Show this help

Environment (CLI flags win):
  KEEP_GPU_FIRMWARE       true|false (default false)
  KAIROS_VERSION          Passed to kairos-init --version (default v4.1.2)
  KAIROS_INIT_VERSION     kairos-init image tag + default output tag (v0.16.2)
  SPECTRO_REPO            Registry/org prefix for the default tag

Examples:
  ./build.sh
  ./build.sh --push
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
    --keep-gpu-firmware) KEEP_GPU_FIRMWARE=true; shift ;;
    --push)              OUTPUT=push; shift ;;
    --no-cache)          NO_CACHE=true; shift ;;
    -h|--help)           usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "Error: docker not found on PATH" >&2; exit 1; }

IMAGE_TAG="${IMAGE_TAG:-${SPECTRO_REPO}/base/ubuntu-uki-24.04:${KAIROS_INIT_VERSION}}"

if [ "${OUTPUT}" = "push" ]; then
  PLATFORMS="linux/amd64,linux/arm64"
else
  # BuildKit cannot --load a multi-arch image into the local daemon.
  PLATFORMS="linux/amd64"
fi

CACHE_ARGS=()
if [ "${NO_CACHE}" = "true" ]; then
  CACHE_ARGS=(--no-cache)
fi

echo "Build configuration:"
echo "  Image tag:           ${IMAGE_TAG}"
echo "  Kairos version:      ${KAIROS_VERSION}"
echo "  kairos-init version: ${KAIROS_INIT_VERSION}"
echo "  KEEP_GPU_FIRMWARE:   ${KEEP_GPU_FIRMWARE}"
echo "  Platforms:           ${PLATFORMS}"
echo "  Output:              ${OUTPUT}"

docker buildx build \
  --progress=plain \
  --platform "${PLATFORMS}" \
  "${CACHE_ARGS[@]}" \
  --build-arg VERSION="${KAIROS_VERSION}" \
  --build-arg KAIROS_INIT_VERSION="${KAIROS_INIT_VERSION}" \
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
