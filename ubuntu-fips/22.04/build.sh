SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Mozilla bug 2083449: provide the distrust script in the build context.
cp "${SCRIPT_DIR}/../../scripts/distrust-emudhra-roots.sh" "${SCRIPT_DIR}/"
trap 'rm -f "${SCRIPT_DIR}/distrust-emudhra-roots.sh"' EXIT
BASE_IMAGE="${1:-ubuntu-jammy-fips}"
VERSION=22.04
DOCKER_BUILDKIT=1 docker build --secret id=pro-attach-config,src=pro-attach-config.yaml -t "$BASE_IMAGE" -f "Dockerfile.ubuntu$VERSION-fips" .