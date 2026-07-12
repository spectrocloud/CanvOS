#!/usr/bin/env bash
#
# build-slem.sh — SLE Micro build.
#
# NOTE: slem/build.sh runs `transactional-update register/install` on the
# BUILD HOST. That means this job must run on a self-hosted runner whose
# OS is SLE Micro. Stock ubuntu-latest cannot execute the current
# slem/build.sh — it will fail on line 37 (`transactional-update: not
# found`).
#
# The base-images.yaml workflow sets `runs-on: self-hosted-slem` for this
# family. Until that runner exists, dispatch users should leave build_slem
# unchecked. Do not silently downgrade to a mock build.

set -euo pipefail

: "${CREDS_DIR:?}"
: "${PE_VERSION:?}"

reg_code_file="$CREDS_DIR/suse_registration_code"
if [ ! -f "$reg_code_file" ]; then
    echo "::error::$reg_code_file is missing — materialize_credentials.sh should have created it"
    exit 1
fi
reg_code="$(cat "$reg_code_file")"

image_tag="${IMAGE_REGISTRY:+$IMAGE_REGISTRY/}slem-base:${PE_VERSION}${CUSTOM_TAG:+-$CUSTOM_TAG}"

# slem/build.sh expects to run FROM the slem/ directory.
pushd slem/ >/dev/null

# Pass the reg code as $1 and image tag as $2. The reg-code value is
# already masked in the log via the workflow's ::add-mask:: call.
bash ./build.sh "$reg_code" "$image_tag"

popd >/dev/null

mkdir -p build
docker save "$image_tag" | gzip > "build/slem-base.tar.gz"

if [ -n "${IMAGE_REGISTRY:-}" ]; then
    docker push "$image_tag"
fi
