#!/usr/bin/env bash
#
# prebuild-amdgpu-artifact.sh
#
# Compile AMD's amdgpu-dkms module against the kairos base image's kernel in a
# host-side `docker run --privileged` container, then tar the resulting kernel
# module + firmware + support files into an artifact the main Earthly build
# COPYs in.
#
# WHY THIS EXISTS
# ---------------
# Earthly's buildkit RUN sandbox breaks AMD's amdgpu-dkms ./configure heredoc
# probe (fails at "cannot detect CFLAGS..."), despite the same script + same
# base image + same host succeeding under plain `docker run --privileged`.
# The specific buildkit-vs-docker sandbox difference is not something we
# control from the Earthfile. Instead of fighting it, we run the DKMS build
# outside Earthly, in the environment we know works, and let Earthly consume
# the produced artifact via COPY.
#
# WHAT ENDS UP IN THE ARTIFACT
#   /lib/modules/<kver>/updates/dkms/<amdgpu modules>.ko*
#   /lib/firmware/amdgpu/*                                   (firmware blobs)
#   /etc/dkms/framework.conf.d/canvos-no-mok-signing.conf    (defensive)
#   /etc/modules-load.d/amdgpu.conf                          (autoload)
#   /etc/canvos/amdgpu-driver-source                         (on-node marker)
#
# Extracting the tar into the image (via the Earthfile) + running depmod on
# the target kernel is functionally equivalent to running install-amdgpu-
# drivers.sh directly in the image.
#
# CACHING
#   Artifacts are stored at build/amdgpu-artifact-<release>-<kver>-<base-sha256>.tar.gz
#   Cache hits when release + base-image digest + kver match. Docker image
#   pulls are hit via the local docker daemon's own cache.
#
# INPUTS (env vars; defaults mirror the Earthfile / .arg.template)
#   BASE_IMAGE                 kairos base image ref (REQUIRED)
#   AMDGPU_DRIVER_RELEASE      default: 7.2.1  (pairs with GPU Operator v1.5.0)
#   AMDGPU_ARTIFACT_DIR        default: ./build
#   AMDGPU_FORCE_REBUILD       set to 1 to bypass cache
#
# OUTPUT (stdout)
#   Absolute path to the produced .tar.gz on the last line, prefixed by
#   "AMDGPU_ARTIFACT_PATH=" so callers can `eval "$(prebuild-amdgpu-artifact.sh)"`
#   or just take the last line.
#
set -euo pipefail

log()  { echo "[prebuild-amdgpu] $*" >&2; }
die()  { echo "[prebuild-amdgpu] ERROR: $*" >&2; exit 1; }

# --- inputs ---------------------------------------------------------------
: "${BASE_IMAGE:?BASE_IMAGE must be set (kairos base image ref, e.g. us-docker.pkg.dev/palette-images/edge/kairos-ubuntu:24.04-core-amd64-generic-v4.0.4)}"
AMDGPU_DRIVER_RELEASE="${AMDGPU_DRIVER_RELEASE:-7.2.1}"
AMDGPU_ARTIFACT_DIR="${AMDGPU_ARTIFACT_DIR:-./build}"
AMDGPU_FORCE_REBUILD="${AMDGPU_FORCE_REBUILD:-0}"

command -v docker >/dev/null 2>&1 || die "docker must be available on the build host."

# The install script we'll run inside the container.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install-amdgpu-drivers.sh"
HEADERS_SCRIPT="${SCRIPT_DIR}/install-kernel-headers.sh"
[ -r "${INSTALL_SCRIPT}" ] || die "cannot find install-amdgpu-drivers.sh at ${INSTALL_SCRIPT}"
[ -r "${HEADERS_SCRIPT}" ] || die "cannot find install-kernel-headers.sh at ${HEADERS_SCRIPT}"

mkdir -p "${AMDGPU_ARTIFACT_DIR}"

# --- discover target kernel + base image digest ---------------------------
log "Pulling base image (may be cached): ${BASE_IMAGE}"
docker pull "${BASE_IMAGE}" >/dev/null || die "failed to pull ${BASE_IMAGE}"

BASE_DIGEST="$(docker image inspect -f '{{.Id}}' "${BASE_IMAGE}" | sed 's/^sha256://' | cut -c1-12)"
[ -n "${BASE_DIGEST}" ] || die "could not read digest of ${BASE_IMAGE}"

KVER="$(docker run --rm --entrypoint /bin/sh "${BASE_IMAGE}" -c 'ls /lib/modules | sort -V | tail -1' 2>/dev/null)"
[ -n "${KVER}" ] || die "could not discover kernel from /lib/modules inside ${BASE_IMAGE}"

ARTIFACT_NAME="amdgpu-artifact-${AMDGPU_DRIVER_RELEASE}-${KVER}-${BASE_DIGEST}.tar.gz"
ARTIFACT_PATH="$(cd "${AMDGPU_ARTIFACT_DIR}" && pwd)/${ARTIFACT_NAME}"

log "Base image digest : ${BASE_DIGEST}"
log "Target kernel     : ${KVER}"
log "Driver release    : ${AMDGPU_DRIVER_RELEASE}"
log "Artifact path     : ${ARTIFACT_PATH}"

# --- cache check ----------------------------------------------------------
if [ "${AMDGPU_FORCE_REBUILD}" != "1" ] && [ -s "${ARTIFACT_PATH}" ]; then
    log "Cache hit -- reusing existing artifact. Set AMDGPU_FORCE_REBUILD=1 to override."
    echo "AMDGPU_ARTIFACT_PATH=${ARTIFACT_PATH}"
    exit 0
fi

# --- build ----------------------------------------------------------------
# Run the install script inside a privileged container against the same base
# image the Earthfile will use, then tar out the produced files. We stream
# the tar over stdout to avoid needing an intermediate volume mount that some
# rootless docker setups can't do cleanly.
STAGE_DIR="$(mktemp -d "${AMDGPU_ARTIFACT_DIR}/.amdgpu-build.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT

log "Compiling amdgpu-dkms in container. This takes ~8-10 min the first time."
docker run --rm --privileged \
    -e AMDGPU_DRIVER_SOURCE=dkms \
    -e AMDGPU_DRIVER_RELEASE="${AMDGPU_DRIVER_RELEASE}" \
    -e AMDGPU_REBUILD_INITRD=false \
    -e KVER_EXPECTED="${KVER}" \
    -v "${INSTALL_SCRIPT}:/tmp/install-amdgpu-drivers.sh:ro" \
    -v "${HEADERS_SCRIPT}:/tmp/install-kernel-headers.sh:ro" \
    --entrypoint /bin/bash \
    "${BASE_IMAGE}" \
    -c '
        set -eo pipefail
        chmod +x /tmp/install-amdgpu-drivers.sh /tmp/install-kernel-headers.sh
        /tmp/install-amdgpu-drivers.sh 1>&2

        # Verify the module actually landed.
        MODDIR="/lib/modules/${KVER_EXPECTED}/updates/dkms"
        if ! find "${MODDIR}" -name "amdgpu.ko*" 2>/dev/null | grep -q .; then
            echo "prebuild: no amdgpu module under ${MODDIR}" >&2
            exit 1
        fi

        # Build the tar to stdout. Paths must exist to be included; the tar
        # is anchored at / so extraction inside the image lands under the
        # same absolute paths.
        TAR_INPUTS=(
            "/lib/modules/${KVER_EXPECTED}/updates/dkms"
            "/etc/modules-load.d/amdgpu.conf"
            "/etc/canvos/amdgpu-driver-source"
        )
        # Firmware + framework drop-in are optional but helpful; skip silently if absent.
        [ -d /lib/firmware/amdgpu ] && TAR_INPUTS+=("/lib/firmware/amdgpu")
        [ -r /etc/dkms/framework.conf.d/canvos-no-mok-signing.conf ] && \
            TAR_INPUTS+=("/etc/dkms/framework.conf.d/canvos-no-mok-signing.conf")

        tar -czf - "${TAR_INPUTS[@]}"
    ' > "${STAGE_DIR}/artifact.tar.gz"

# Sanity: tar file must be non-empty and contain the amdgpu module.
[ -s "${STAGE_DIR}/artifact.tar.gz" ] || die "prebuild produced an empty artifact."
if ! tar -tzf "${STAGE_DIR}/artifact.tar.gz" | grep -q "updates/dkms/amdgpu.ko"; then
    die "artifact does not contain an amdgpu module under updates/dkms/; \
inspect ${STAGE_DIR}/artifact.tar.gz."
fi

mv "${STAGE_DIR}/artifact.tar.gz" "${ARTIFACT_PATH}"
log "Artifact produced ($(du -h "${ARTIFACT_PATH}" | awk '{print $1}'))."

# --- output ---------------------------------------------------------------
echo "AMDGPU_ARTIFACT_PATH=${ARTIFACT_PATH}"
