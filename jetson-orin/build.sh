#!/bin/bash
docker buildx build --platform linux/arm64 --push . -t gcr.io/spectro-dev-public/stylus/ubuntu-jetson-orin:20.04-v3.0.5 -f Dockerfile