#!/bin/bash
# Build a bootable Kairos SLE Micro (for Rancher) 5.5 base image on any host
# with Docker + BuildKit.
#
# registry.suse.com/suse/sle-micro/5.5 is the "SLE Micro for Rancher 5.5" image.
# To get a *bootable* Kairos image, kairos-init must install a kernel + dracut
# that match the base (mixing in older openSUSE Leap packages produces an
# unbootable initrd). We therefore register against SCC at build time to pull
# the version-matched SLE 15 SP5 repos.
#
# Usage: ./build.sh <REGISTRATION_CODE> [<OUTPUT_TAG>]

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "ERROR : Registration code is empty !"
  echo "Re-run with a SUSE registration code, e.g.: ./build.sh 1234567890 [slem-kairos:5.5]"
  exit 1
fi

REGISTRATION_CODE="$1"
OUTPUT_TAG="${2:-slem-kairos:5.5}"

cd "$(dirname "$0")"

# Pass the regcode as a BuildKit secret so it never lands in an image layer.
REGCODE_FILE="$(mktemp)"
trap 'rm -f "${REGCODE_FILE}"' EXIT
printf '%s' "${REGISTRATION_CODE}" > "${REGCODE_FILE}"

echo "==> Building ${OUTPUT_TAG} (SCC-registered SLE Micro 5.5) ..."
DOCKER_BUILDKIT=1 docker build \
  --secret "id=SUSE_REGCODE,src=${REGCODE_FILE}" \
  -t "${OUTPUT_TAG}" \
  .

echo "==> Done: ${OUTPUT_TAG}"
