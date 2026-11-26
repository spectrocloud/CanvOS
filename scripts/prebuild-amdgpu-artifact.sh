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
#   AMDGPU_DRIVER_RELEASE      default: 31.40 (ROCm 7.14 GA; pairs with GPU Operator v1.5.1)
#   AMDGPU_ARTIFACT_DIR        default: ./build
#   AMDGPU_FORCE_REBUILD       set to 1 to bypass cache
#   GPU_MODULE_SIGNING         required (default) | off. Secure Boot module signing.
#                              required: MOK_PRIV + MOK_DER (key and cert content, as
#                              Vault hands them over) must be set, every module is
#                              signed and verified on THIS host after the container
#                              build, and the build fails otherwise. The key is never
#                              mounted into the DKMS container, which runs third-party
#                              package scripts. off: produce an unsigned artifact.
#
# SIGNING IDENTITY AND THE CACHE
#   The signing certificate's SHA-256 is part of the artifact file name
#   (...-s<12 hex>.tar.gz; unsigned builds use -unsigned). A cached unsigned artifact,
#   or one signed by another key, therefore never matches a signed build and can't
#   stand in for it. The tarball also carries the public cert as
#   /etc/canvos/gpu-module-signer.der, which install-amdgpu-drivers.sh verifies
#   against the pinned GPU_MODULE_SIGN_CERT_SHA256 before the modules reach the image.
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
AMDGPU_DRIVER_RELEASE="${AMDGPU_DRIVER_RELEASE:-31.40}"
AMDGPU_ARTIFACT_DIR="${AMDGPU_ARTIFACT_DIR:-./build}"
AMDGPU_FORCE_REBUILD="${AMDGPU_FORCE_REBUILD:-0}"
GPU_MODULE_SIGNING="${GPU_MODULE_SIGNING:-required}"

command -v docker >/dev/null 2>&1 || die "docker must be available on the build host."

# The install script we'll run inside the container.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install-amdgpu-drivers.sh"
HEADERS_SCRIPT="${SCRIPT_DIR}/install-kernel-headers.sh"
SIGN_SCRIPT="${SCRIPT_DIR}/sign-kernel-modules.sh"
[ -r "${INSTALL_SCRIPT}" ] || die "cannot find install-amdgpu-drivers.sh at ${INSTALL_SCRIPT}"
[ -r "${HEADERS_SCRIPT}" ] || die "cannot find install-kernel-headers.sh at ${HEADERS_SCRIPT}"
[ -r "${SIGN_SCRIPT}" ] || die "cannot find sign-kernel-modules.sh at ${SIGN_SCRIPT}"

# --- signing identity (fails fast, before the 8-10 minute compile) ---------
case "${GPU_MODULE_SIGNING}" in
    required)
        # check-key fails when MOK_PRIV / MOK_DER are absent, unparsable or not a pair.
        bash "${SIGN_SCRIPT}" check-key \
            || die "GPU_MODULE_SIGNING=required but no usable signing key: set MOK_PRIV and MOK_DER (from Vault). \
Use GPU_MODULE_SIGNING=off only for builds that don't need Secure Boot."
        SIGN_FP="$(bash "${SIGN_SCRIPT}" fingerprint)"
        [ -n "${SIGN_FP}" ] || die "could not compute the signing certificate fingerprint."
        SIGN_ID="s${SIGN_FP:0:12}"
        ;;
    off)
        SIGN_FP=""
        SIGN_ID="unsigned"
        log "WARNING: GPU_MODULE_SIGNING=off -- the artifact will be UNSIGNED and will not load under Secure Boot."
        ;;
    *) die "GPU_MODULE_SIGNING must be 'required' or 'off' (got: '${GPU_MODULE_SIGNING}')." ;;
esac

mkdir -p "${AMDGPU_ARTIFACT_DIR}"

# --- discover target kernel + base image digest ---------------------------
log "Pulling base image (may be cached): ${BASE_IMAGE}"
docker pull "${BASE_IMAGE}" >/dev/null || die "failed to pull ${BASE_IMAGE}"

BASE_DIGEST="$(docker image inspect -f '{{.Id}}' "${BASE_IMAGE}" | sed 's/^sha256://' | cut -c1-12)"
[ -n "${BASE_DIGEST}" ] || die "could not read digest of ${BASE_IMAGE}"

KVER="$(docker run --rm --entrypoint /bin/sh "${BASE_IMAGE}" -c 'ls /lib/modules | sort -V | tail -1' 2>/dev/null)"
[ -n "${KVER}" ] || die "could not discover kernel from /lib/modules inside ${BASE_IMAGE}"

ARTIFACT_NAME="amdgpu-artifact-${AMDGPU_DRIVER_RELEASE}-${KVER}-${BASE_DIGEST}-${SIGN_ID}.tar.gz"
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
    -e AMDGPU_INSTALL_SMI=false \
    -e GPU_MODULE_SIGNING="${GPU_MODULE_SIGNING}" \
    -e GPU_MODULE_SIGNING_DEFERRED=1 \
    -e KVER_EXPECTED="${KVER}" \
    -v "${INSTALL_SCRIPT}:/tmp/install-amdgpu-drivers.sh:ro" \
    -v "${HEADERS_SCRIPT}:/tmp/install-kernel-headers.sh:ro" \
    --entrypoint /bin/bash \
    "${BASE_IMAGE}" \
    -c '
        set -eo pipefail
        # Scripts are bind-mounted read-only from the host; invoke via `bash`
        # so we don t need chmod +x (which would fail on the RO mount).
        bash /tmp/install-amdgpu-drivers.sh 1>&2

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

[ -s "${STAGE_DIR}/artifact.tar.gz" ] || die "prebuild produced an empty artifact."

# --- sign on the host -------------------------------------------------------
# The container above compiled the modules and ran AMD's package scripts, so the
# key was kept out of it. Here, with only the modules in hand, sign every one,
# ship the public cert in the artifact, verify, and repack. The final file name
# is only ever written with a signed artifact, so a failure here leaves nothing
# a later run (or the cache check above) could pick up.
if [ "${GPU_MODULE_SIGNING}" = "required" ]; then
    log "Signing amdgpu modules (cert SHA-256 ${SIGN_FP}) ..."
    SIGN_DIR="${STAGE_DIR}/signing"
    mkdir -p "${SIGN_DIR}"
    tar -xpzf "${STAGE_DIR}/artifact.tar.gz" -C "${SIGN_DIR}" || die "could not unpack the staged artifact for signing."
    MODDIR="${SIGN_DIR}/lib/modules/${KVER}/updates"
    [ -d "${MODDIR}" ] || die "staged artifact has no modules under lib/modules/${KVER}/updates."

    bash "${SIGN_SCRIPT}" sign "${KVER}" "${MODDIR}" \
        || die "signing failed; no artifact was written."
    bash "${SIGN_SCRIPT}" export-cert "${SIGN_DIR}/etc/canvos/gpu-module-signer.der" \
        || die "could not add the signing certificate to the artifact."
    GPU_MODULE_SIGN_CERT_FILE="${SIGN_DIR}/etc/canvos/gpu-module-signer.der" \
    GPU_MODULE_SIGN_CERT_SHA256="${SIGN_FP}" \
        bash "${SIGN_SCRIPT}" verify "${MODDIR}" \
        || die "post-sign verification failed; no artifact was written."

    # Repack files only (no directory entries): extracting a "lib/" entry over the
    # image's /lib -> usr/lib symlink would replace the symlink with a directory.
    ( cd "${SIGN_DIR}" && find . \( -type f -o -type l \) | sed 's#^\./##' | LC_ALL=C sort > "${STAGE_DIR}/files.list" )
    TAR_OWNER=()
    tar --version 2>/dev/null | grep -qi 'gnu tar' && TAR_OWNER=(--owner=0 --group=0 --numeric-owner)
    tar -C "${SIGN_DIR}" "${TAR_OWNER[@]}" --no-recursion -czf "${STAGE_DIR}/signed.tar.gz" -T "${STAGE_DIR}/files.list" \
        || die "could not repack the signed artifact."
    mv "${STAGE_DIR}/signed.tar.gz" "${STAGE_DIR}/artifact.tar.gz"
fi

# Move the artifact to its final path IMMEDIATELY after the checks above so a
# subsequent sanity failure leaves a diagnosable file behind (STAGE_DIR is wiped
# by the trap).
mv "${STAGE_DIR}/artifact.tar.gz" "${ARTIFACT_PATH}"

# Sanity: tar file must be a valid gzip and contain the amdgpu module.
tar_listing="$(tar -tzf "${ARTIFACT_PATH}" 2>&1)" \
    || die "artifact ${ARTIFACT_PATH} is not a valid gzipped tar. Head of output: $(printf '%s\n' "${tar_listing}" | head -3)"
if ! printf '%s\n' "${tar_listing}" | grep -qE "updates/dkms/.*amdgpu\.ko"; then
    log "Artifact contents (first 40 entries):"
    printf '%s\n' "${tar_listing}" | head -40 | sed 's/^/    /' >&2
    die "artifact ${ARTIFACT_PATH} does not contain an amdgpu module under updates/dkms/. \
The tarball is preserved for inspection. Delete it and rerun with \
AMDGPU_FORCE_REBUILD=1 to try again."
fi

if [ "${GPU_MODULE_SIGNING}" = "required" ]; then
    printf '%s\n' "${tar_listing}" | grep -q 'etc/canvos/gpu-module-signer.der' \
        || die "artifact ${ARTIFACT_PATH} lacks the signing certificate; refusing to publish it."
fi

log "Artifact produced ($(du -h "${ARTIFACT_PATH}" | awk '{print $1}')), signing: ${SIGN_ID}."

# --- output ---------------------------------------------------------------
echo "AMDGPU_ARTIFACT_PATH=${ARTIFACT_PATH}"
