#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET=all
FIPS=false
KAIROS_VERSION=v4.1.0
HADRON_VERSION="${HADRON_VERSION:-v0.4.0}"
OUTPUT=""
MODULES_IMAGE="${MODULES_IMAGE:-}"
HADRON_IMAGE=""

default_modules_image() {
  echo "us-east1-docker.pkg.dev/spectro-images/dev/arun/hadron/modules:${HADRON_VERSION}"
}

usage() {
  cat <<'EOF'
Usage: build.sh [OPTIONS]

Build Spectro modules (additional OS packages for hadron) and/or the Hadron base image.

Targets:
  --target modules    Build the modules image only
  --target hadron     Build the Hadron base image only
  --target all        Build modules, then Hadron (default)

Options:
  --fips              Build with FIPS base image and enable FIPS mode
  --hadron-version V  Upstream Hadron version tag (default: v0.4.0)
  --push              Build modules locally, then push the Hadron image
  --modules-image TAG Modules image reference for the Hadron build
  --hadron-image TAG  Hadron image reference (overrides default)
  -h, --help          Show this help

Defaults:
  ./build.sh                  Build modules and Hadron, load both locally
  ./build.sh --push           Build modules locally, then build and push Hadron
  ./build.sh --target hadron  Build Hadron only, load locally
  ./build.sh --target modules Build modules only, load locally

Environment:
  MODULES_IMAGE     Modules image reference (same as --modules-image)
  HADRON_VERSION    Upstream Hadron version tag (same as --hadron-version)

Examples:
  ./build.sh
  ./build.sh --push
  ./build.sh --hadron-version v0.5.0
  ./build.sh --target hadron --modules-image hadron-modules-local:dev
  ./build.sh --hadron-image myrepo/hadron:latest
  ./build.sh --target modules --push
EOF
  exit "${1:-0}"
}

default_hadron_image() {
  if [ "${FIPS}" = "true" ]; then
    echo "us-east1-docker.pkg.dev/spectro-images/dev/arun/base/hadron-fips-${HADRON_VERSION}:${KAIROS_VERSION}"
  else
    echo "us-east1-docker.pkg.dev/spectro-images/dev/arun/base/hadron-${HADRON_VERSION}:${KAIROS_VERSION}"
  fi
}

local_modules_tag() {
  echo "hadron-modules-local:$(date +%s)"
}

docker_output_flag() {
  case "$1" in
    load|push) echo "--$1" ;;
    *) echo "unknown docker output mode: $1" >&2; exit 1 ;;
  esac
}

build_modules() {
  local tag="$1"
  local output_mode="$2"
  local output_flag
  output_flag="$(docker_output_flag "${output_mode}")"

  echo "Building modules image: ${tag}"
  DOCKER_BUILDKIT=1 docker build \
    --platform "linux/amd64,linux/arm64" \
    -f "${SCRIPT_DIR}/Dockerfile.modules" \
    -t "${tag}" \
    --build-arg HADRON_VERSION="${HADRON_VERSION}" \
    "${output_flag}" \
    "${SCRIPT_DIR}"
  echo "Built modules: ${tag}"
}

build_hadron() {
  local modules_image="$1"
  local hadron_image="$2"
  local output_mode="$3"
  local output_flag
  output_flag="$(docker_output_flag "${output_mode}")"

  echo "Building Hadron image: ${hadron_image} (modules: ${modules_image})"
  DOCKER_BUILDKIT=1 docker build \
    --platform "linux/amd64,linux/arm64" \
    --build-arg KAIROS_VERSION="${KAIROS_VERSION}" \
    --build-arg HADRON_VERSION="${HADRON_VERSION}" \
    --build-arg FIPS="${FIPS}" \
    --build-arg MODULES_IMAGE="${modules_image}" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    -t "${hadron_image}" \
    "${output_flag}" \
    "${SCRIPT_DIR}"
  echo "Built Hadron: ${hadron_image}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -gt 1 ]] || { echo "--target requires an argument" >&2; usage 1; }
      TARGET="$2"
      shift 2
      ;;
    --fips)
      FIPS=true
      shift
      ;;
    --hadron-version)
      [[ $# -gt 1 ]] || { echo "--hadron-version requires an argument" >&2; usage 1; }
      HADRON_VERSION="$2"
      shift 2
      ;;
    --push)
      OUTPUT=push
      shift
      ;;
    --modules-image)
      [[ $# -gt 1 ]] || { echo "--modules-image requires an argument" >&2; usage 1; }
      MODULES_IMAGE="$2"
      shift 2
      ;;
    --hadron-image)
      [[ $# -gt 1 ]] || { echo "--hadron-image requires an argument" >&2; usage 1; }
      HADRON_IMAGE="$2"
      shift 2
      ;;
    -h|--help)
      usage 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *)
      echo "Unexpected argument: $1" >&2
      usage 1
      ;;
  esac
done

case "${TARGET}" in
  modules|hadron|all) ;;
  *)
    echo "Invalid target: ${TARGET} (expected modules, hadron, or all)" >&2
    usage 1
    ;;
esac

if [ "${TARGET}" = "modules" ] || [ "${TARGET}" = "all" ]; then
  MODULES_IMAGE="${MODULES_IMAGE:-$(local_modules_tag)}"
fi

if [ "${TARGET}" = "hadron" ] || [ "${TARGET}" = "all" ]; then
  HADRON_IMAGE="${HADRON_IMAGE:-$(default_hadron_image)}"
fi

# List the build configuration
echo "Build configuration:"
echo "  Target: ${TARGET}"
echo "  FIPS: ${FIPS}"
echo "  Hadron version: ${HADRON_VERSION}"
echo "  Modules image: ${MODULES_IMAGE}"
echo "  Output mode: ${OUTPUT:-load}"

if [ "${TARGET}" = "hadron" ] || [ "${TARGET}" = "all" ]; then
  echo "  Hadron image: ${HADRON_IMAGE}"
fi



case "${TARGET}" in
  modules)
    build_modules "${MODULES_IMAGE}" "${OUTPUT:-load}"
    ;;
  hadron)
    build_hadron "${MODULES_IMAGE:-$(default_modules_image)}" "${HADRON_IMAGE}" "${OUTPUT:-load}"
    ;;
  all)
    modules_output="load"
    if [ "${OUTPUT}" = "push" ]; then
      hadron_output="push"
    else
      hadron_output="load"
    fi
    build_modules "${MODULES_IMAGE}" "${modules_output}"
    build_hadron "${MODULES_IMAGE}" "${HADRON_IMAGE}" "${hadron_output}"
    ;;
esac
