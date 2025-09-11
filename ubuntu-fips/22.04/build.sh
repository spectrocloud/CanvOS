BASE_IMAGE="${1:-ubuntu-jammy-fips}"
VERSION=22.04
DOCKER_BUILDKIT=1 docker build --secret id=pro-attach-config,src=pro-attach-config.yaml -t "$BASE_IMAGE" -f "Dockerfile.ubuntu$VERSION-fips-new" .