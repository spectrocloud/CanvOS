BASE_IMAGE="${1:-ubuntu-focal-fips}"
VERSION=20.04
DOCKER_BUILDKIT=1 docker build --secret id=pro-attach-config,src=pro-attach-config.yaml -t "$BASE_IMAGE" -f "Dockerfile.ubuntu$VERSION-fips" .