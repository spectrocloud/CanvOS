#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET=hadron
FIPS=false
IS_UKI=false
OUTPUT=load
NO_CACHE=false
HADRON_VERSION="${HADRON_VERSION:-v0.5.1}"
KAIROS_VERSION="${KAIROS_VERSION:-v4.1.2}"
KAIROS_INIT_VERSION="${KAIROS_INIT_VERSION:-v0.16.3}"
KAIROS_INIT_IMAGE="${KAIROS_INIT_IMAGE:-quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION}}"
SPECTRO_REPO="${SPECTRO_REPO:-us-east1-docker.pkg.dev/spectro-images/dev/arun}"
MODULES_IMAGE=""

default_modules_image() {
	echo "$SPECTRO_REPO/hadron-modules:${HADRON_VERSION}"
}

hadron_image_tag() {
	local variant=""
	if [ "${FIPS}" = "true" ]; then
		variant="-fips"
	elif [ "${IS_UKI}" = "true" ]; then
		variant="-uki"
	fi
	echo "${SPECTRO_REPO}/kairos-hadron:${HADRON_VERSION}-core-generic-${KAIROS_INIT_VERSION}${variant}"
}

platforms() {
	# Multi-arch on push, linux/amd64 on local load (BuildKit can't load multi-arch
	# images into the local docker daemon).
	if [ "${OUTPUT}" = "push" ]; then
	  	echo "linux/amd64,linux/arm64"
	else
	  	echo "linux/amd64"
	fi
}

build_modules_image() {
	docker buildx build \
		--progress=plain \
		--platform "$(platforms)" \
		"${CACHE_ARGS[@]}" \
		-f "${SCRIPT_DIR}/Dockerfile.modules" \
		-t "${MODULES_IMAGE}" \
		--build-arg HADRON_VERSION="${HADRON_VERSION}" \
		"--${OUTPUT}" \
		"${SCRIPT_DIR}"
}

build_hadron_image() {
	docker buildx build \
		--progress=plain \
		--platform "$(platforms)" \
		"${CACHE_ARGS[@]}" \
		--build-arg KAIROS_VERSION="${KAIROS_VERSION}" \
		--build-arg KAIROS_INIT_VERSION="${KAIROS_INIT_VERSION}" \
		--build-arg KAIROS_INIT_IMAGE="${KAIROS_INIT_IMAGE}" \
		--build-arg HADRON_VERSION="${HADRON_VERSION}" \
		--build-arg FIPS="${FIPS}" \
		--build-arg IS_UKI="${IS_UKI}" \
		--build-arg MODULES_IMAGE="${MODULES_IMAGE}" \
		-f "${SCRIPT_DIR}/Dockerfile" \
		-t "${HADRON_IMAGE}" \
		"--${OUTPUT}" \
		"${SCRIPT_DIR}"
}


validate() {
	if ! command -v docker >/dev/null 2>&1; then
		echo "Error: docker not found on PATH" >&2
		exit 1
	fi

  	case "${TARGET}" in
  	  	modules|hadron) ;;
  	  	*) echo "Invalid target: ${TARGET} (expected modules or hadron)" >&2; usage 1 ;;
  	esac

  	if [ "${FIPS}" = "true" ] && [ "${IS_UKI}" = "true" ]; then
    	echo "Error: --fips and --uki cannot be combined (UKI is not supported in FIPS mode)" >&2
    	exit 1
  	fi
}


usage() {
  cat <<'EOF'
Usage: build.sh [OPTIONS]

Build the Hadron base image (default) or the Spectro modules image.

Options:
  --target {hadron|modules}   Image to build (default: hadron)
  --fips                      Use the FIPS base image and enable FIPS mode
  --uki                       Trusted boot. Not compatible with --fips.
  --push                      Push the resulting image (multi-arch:
                              linux/amd64,linux/arm64). Default(--load).
  --no-cache                  Pass --no-cache to docker buildx build
  --modules-image TAG         Override the modules image tag. Defaults to
                              ${SPECTRO_REPO}/hadron-modules:${HADRON_VERSION}.
  -h, --help                  Show this help

Environment (override defaults; CLI flags always win):
  HADRON_VERSION          Upstream Hadron version tag (default: v0.5.1)
  KAIROS_VERSION          Kairos version passed to kairos-init --version
                          (default: v4.1.2). Not used in the image tag.
  KAIROS_INIT_VERSION     kairos-init image tag. This is
                          also the tag of the built Hadron image.
  KAIROS_INIT_IMAGE       Complete kairos-init image reference.
						  
  SPECTRO_REPO            Registry + org prefix for all built images
                          (default: us-east1-docker.pkg.dev/spectro-images/dev/arun)

Examples:
  ./build.sh --fips --push                              # FIPS variant, pushed
  ./build.sh --uki                                      # UKI variant, loaded locally
  ./build.sh --target modules --push                    # build & push modules only
  HADRON_VERSION=v0.6.0 ./build.sh --push               # override Hadron version via env
  SPECTRO_REPO=myrepo.example.com/team ./build.sh --push  # publish under a different registry/org
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -gt 1 ]] || { echo "--target requires an argument" >&2; usage 1; }
      TARGET="$2"
      shift 2
      ;;
    --fips)          FIPS=true;   shift ;;
    --uki)           IS_UKI=true; shift ;;
    --push)          OUTPUT=push; shift ;;
    --no-cache)      NO_CACHE=true; shift ;;
    --modules-image)
      [[ $# -gt 1 ]] || { echo "--modules-image requires an argument" >&2; usage 1; }
      MODULES_IMAGE="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done


validate

CACHE_ARGS=()
if [ "${NO_CACHE}" = "true" ]; then
	CACHE_ARGS=(--no-cache)
fi

echo "Build configuration:"
echo "  Target: ${TARGET}"
echo "  FIPS: ${FIPS}"
echo "  Trusted Boot (UKI): ${IS_UKI}"
echo "  Hadron version: ${HADRON_VERSION}"
echo "  Kairos version: ${KAIROS_VERSION}"
echo "  kairos-init version: ${KAIROS_INIT_VERSION}"
echo "  kairos-init image: ${KAIROS_INIT_IMAGE}"
echo "  Output mode: ${OUTPUT}"
echo "  No cache: ${NO_CACHE}"

MODULES_IMAGE="${MODULES_IMAGE:-$(default_modules_image)}"
echo "  Modules image: ${MODULES_IMAGE}"

if [ "${TARGET}" = "modules" ]; then
  build_modules_image
  exit 0
fi

HADRON_IMAGE="$(hadron_image_tag)"
echo "  Hadron image: ${HADRON_IMAGE}"

build_hadron_image
