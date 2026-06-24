#!/bin/bash
# Build a Kairos SLE Micro (for Rancher) 5.5 base image on any host with Docker.
#
# registry.suse.com/suse/sle-micro/5.5 is the "SLE Micro for Rancher 5.5" image,
# which kairos-init builds using the public openSUSE Leap 15.5 OSS repo. No SUSE
# subscription / registration code is required.
#
# Usage: ./build.sh [<OUTPUT_TAG>]

set -euo pipefail

OUTPUT_TAG="${1:-slem-kairos:5.5}"

cd "$(dirname "$0")"

echo "==> Building ${OUTPUT_TAG} from registry.suse.com/suse/sle-micro/5.5:latest ..."
docker build -t "${OUTPUT_TAG}" .

echo "==> Done: ${OUTPUT_TAG}"
