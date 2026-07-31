#!/bin/bash
# Build a RHEL Kairos base image registered against a Red Hat Satellite.
# For a direct Red Hat Subscription, use build.sh instead.
#
# Usage:
#   export KEYNAME='<activation key>'
#   bash build-sat.sh <8|9|10> --org <org> --satellite <satellite host> \
#        [--base-image <mirrored ubi image>] [--kairos-init <mirrored kairos-init image>] \
#        [--tag <image name>]

set -euo pipefail

usage() {
  echo "usage: KEYNAME=<key> bash build-sat.sh <8|9|10> --org <org> --satellite <host> [--base-image X] [--kairos-init Y] [--tag Z]" >&2
  exit 1
}

VER="${1:-}"; shift || usage
case "$VER" in
  8|9|10) ;;
  *) echo "ERROR: unsupported RHEL version '$VER' (expected 8, 9 or 10)" >&2; usage ;;
esac

ORGNAME=""; SATHOSTNAME=""; BASE_IMAGE=""; KAIROS_INIT_IMAGE=""; IMAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --org)         ORGNAME="${2:?--org needs a value}"; shift 2 ;;
    --satellite)   SATHOSTNAME="${2:?--satellite needs a value}"; shift 2 ;;
    --base-image)  BASE_IMAGE="${2:?--base-image needs a value}"; shift 2 ;;
    --kairos-init) KAIROS_INIT_IMAGE="${2:?--kairos-init needs a value}"; shift 2 ;;
    --tag)         IMAGE="${2:?--tag needs a value}"; shift 2 ;;
    *) echo "ERROR: unknown option '$1'" >&2; usage ;;
  esac
done

DOCKERFILE="Dockerfile.rhel${VER}.sat"
[ -f "$DOCKERFILE" ] || { echo "ERROR: $DOCKERFILE not found (run from rhel-core-images/)" >&2; exit 1; }

: "${KEYNAME:?export KEYNAME before running (Satellite activation key)}"
[ -n "$ORGNAME" ]     || { echo "ERROR: --org is required" >&2; usage; }
[ -n "$SATHOSTNAME" ] || { echo "ERROR: --satellite is required" >&2; usage; }

IMAGE="${IMAGE:-palette-rhel${VER}:latest}"

BUILD_ARGS=(--build-arg "ORGNAME=$ORGNAME" --build-arg "SATHOSTNAME=$SATHOSTNAME")
[ -n "$BASE_IMAGE" ]        && BUILD_ARGS+=(--build-arg "BASE_IMAGE=$BASE_IMAGE")
[ -n "$KAIROS_INIT_IMAGE" ] && BUILD_ARGS+=(--build-arg "KAIROS_INIT_IMAGE=$KAIROS_INIT_IMAGE")


echo "Building $IMAGE from $DOCKERFILE (org=$ORGNAME satellite=$SATHOSTNAME) ..."
docker build \
  --secret id=KEYNAME,env=KEYNAME \
  "${BUILD_ARGS[@]}" \
  -t "$IMAGE" \
  -f "$DOCKERFILE" .
