#!/bin/bash
docker buildx build --platform linux/arm64 --push . -t gcr.io/spectro-dev-public/stylus/ubuntu-jetson:20.04-v2.4.5 -f Dockerfile