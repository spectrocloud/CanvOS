#!/bin/bash

set -ex

USERNAME=$1
PASSWORD=$2
BASE_IMAGE="${3:-rhel-byoi-fips}"

# Build the container image
docker build --build-arg USERNAME=$USERNAME --build-arg PASSWORD=$PASSWORD -t $BASE_IMAGE .

docker run -v "$PWD"/build:/tmp/auroraboot \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --rm -ti quay.io/kairos/auroraboot \
        --set container_image=docker://$BASE_IMAGE \
        --set "disable_http_server=true" \
        --set "disable_netboot=true" \
        --set "state_dir=/tmp/auroraboot"
