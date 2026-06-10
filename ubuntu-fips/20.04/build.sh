SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root is used as the build context so the Dockerfile can COPY hardware/udev rules.
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BASE_IMAGE="${1:-ubuntu-focal-fips}"

DOCKER_BUILDKIT=1 docker build \
  --secret id=pro-attach-config,src="${SCRIPT_DIR}/pro-attach-config.yaml" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  -t "$BASE_IMAGE" \
  "${REPO_ROOT}"