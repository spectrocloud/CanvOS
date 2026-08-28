#!/bin/bash
# Build a RHEL FIPS Kairos base image.
#
# Usage:
#   export RHSM_USERNAME='you@example.com'
#   export RHSM_PASSWORD='...'
#   bash build.sh --ver <8|9|10> [--tag <image>] [--push]
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: RHSM_USERNAME=... RHSM_PASSWORD=... bash build.sh --ver <8|9|10> [--tag <image>] [--push]

  --ver <8|9|10>   RHEL major version; selects Dockerfile.rhel<N>   (required)
  --tag <image>    image name to build   (default: rhel<N>-byoi-fips)
  --push           docker push the image after a successful build; requires --tag
EOF
  exit 1
}

VER=""; IMAGE=""; PUSH=false
while [ $# -gt 0 ]; do
  case "$1" in
    --ver)     VER="${2:?--ver needs a value}"; shift 2 ;;
    --tag)     IMAGE="${2:?--tag needs a value}"; shift 2 ;;
    --push)    PUSH=true; shift ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown option '$1'" >&2; usage ;;
  esac
done

[ -n "$VER" ] || { echo "ERROR: --ver is required" >&2; usage; }
case "$VER" in
  8|9|10) ;;
  *) echo "ERROR: unsupported RHEL version '$VER' (expected 8, 9 or 10)" >&2; exit 1 ;;
esac

DOCKERFILE="Dockerfile.rhel${VER}"
[ -f "$DOCKERFILE" ] || { echo "ERROR: $DOCKERFILE not found (run from rhel-fips/)" >&2; exit 1; }

# --push needs a registry-qualified name. The default is a bare local name, so pushing it
# would either fail or, worse, target Docker Hub — refuse rather than guess.
if [ "$PUSH" = true ] && [ -z "$IMAGE" ]; then
  echo "ERROR: --push requires --tag with a registry path (e.g. --tag registry.example.com/rhel${VER}-byoi-fips:v1)" >&2
  exit 1
fi

# Consistent naming across versions. build.sh.rhel8 used to default to "rhel-byoi-fips"
# without the 8, so building 8 and then 9 produced inconsistently named images.
IMAGE="${IMAGE:-rhel${VER}-byoi-fips}"

: "${RHSM_USERNAME:?export RHSM_USERNAME before running (Red Hat Subscription Manager username)}"
: "${RHSM_PASSWORD:?export RHSM_PASSWORD before running (Red Hat Subscription Manager password)}"


PUSH_ARG=""
if [ "$PUSH" = true ]; then
  PUSH_ARG="--push"
fi

echo "Building $IMAGE from $DOCKERFILE ..."
docker build \
  --secret id=RHSM_USERNAME,env=RHSM_USERNAME \
  --secret id=RHSM_PASSWORD,env=RHSM_PASSWORD \
  -t "$IMAGE" \
  -f "$DOCKERFILE" \
  $PUSH_ARG .
