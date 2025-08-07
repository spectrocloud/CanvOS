BASE_IMAGE="${1:-ubuntu-jammy-fips}"

DOCKER_BUILDKIT=1 docker build . --secret id=pro-attach-config,src=pro-attach-config.yaml -t "$BASE_IMAGE"