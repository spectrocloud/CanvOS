#!/usr/bin/env bash
#
# build-slem.sh — SLE Micro build.
#
# NOTE: slem/build.sh runs `transactional-update register/install` on the
# BUILD HOST. This job MUST run on a self-hosted runner whose OS is
# SLE Micro. base-images.yaml sets `runs-on: self-hosted-slem` for this
# family; until that runner exists, this row won't complete.

set -euo pipefail

: "${CREDS_DIR:?}"
: "${PE_VERSION:?}"

reg_code_file="$CREDS_DIR/suse_registration_code"
if [ ! -f "$reg_code_file" ]; then
    echo "::error::$reg_code_file is missing — materialize_credentials.sh should have created it"
    exit 1
fi
reg_code="$(cat "$reg_code_file")"

image_tag="slem-base:${PE_VERSION}"

pushd slem/ >/dev/null
bash ./build.sh "$reg_code" "$image_tag"
popd >/dev/null

mkdir -p build
docker save "$image_tag" | gzip > "build/slem-base.tar.gz"
