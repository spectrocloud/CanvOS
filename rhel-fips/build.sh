#!/bin/bash


USERNAME=$1
PASSWORD=$2
BASE_IMAGE="${3:-rhel-byoi-fips}"

# Build the container image
docker build --no-cache --progress=plain --build-arg USERNAME="$USERNAME" --build-arg PASSWORD="$PASSWORD" -t "$BASE_IMAGE" .
