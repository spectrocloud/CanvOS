#!/bin/bash
# Build a Kairos SLE Micro 5.5 base image on any host with Docker + BuildKit.
#
# Unlike the old flow, this does NOT need to run on a registered SLE Micro host.
# Registration happens inside the container build via SUSEConnect, using the
# registration code passed as a BuildKit secret, which enables the version-matched
# SLE 15 SP5 repos.
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
BASE_IMAGE="registry.suse.com/suse/sle-micro/5.5:latest"

cd "$(dirname "$0")"

# Preflight: confirm the base image actually ships SUSEConnect before we build.
echo "==> Checking that ${BASE_IMAGE} provides SUSEConnect ..."
if ! docker run --rm "${BASE_IMAGE}" sh -c 'command -v SUSEConnect' >/dev/null 2>&1; then
  echo "ERROR : SUSEConnect not found in ${BASE_IMAGE}."
  echo "        Install it in the Dockerfile first, or use container-suseconnect."
  exit 1
fi

# Pass the regcode as a BuildKit secret so it never lands in an image layer.
REGCODE_FILE="$(mktemp)"
trap 'rm -f "${REGCODE_FILE}"' EXIT
printf '%s' "${REGISTRATION_CODE}" > "${REGCODE_FILE}"

echo "==> Building ${OUTPUT_TAG} from ${BASE_IMAGE} ..."
DOCKER_BUILDKIT=1 docker build \
  --secret "id=SUSE_REGCODE,src=${REGCODE_FILE}" \
  -t "${OUTPUT_TAG}" \
  .

echo "==> Done: ${OUTPUT_TAG}"
