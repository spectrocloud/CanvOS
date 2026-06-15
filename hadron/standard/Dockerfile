ARG EXTRAS_IMAGE=us-east1-docker.pkg.dev/spectro-images/dev/arun/hadron/extras-modules:v0.3.3-rc2
ARG BASE_IMAGE=ghcr.io/kairos-io/hadron:v0.3.3-rc2
ARG KAIROS_INIT_VERSION=v0.14.4
ARG KAIROS_VERSION=v4.1.0

FROM ${EXTRAS_IMAGE} AS extras

FROM quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION} AS kairos-init

FROM ${BASE_IMAGE} AS base-kairos
ARG MODEL=generic
ARG TRUSTED_BOOT=false
ARG KAIROS_VERSION=v4.0.3

COPY --from=extras / /

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install -m "generic" -t "false" --version "${KAIROS_VERSION}" 

# kairos-init normalizes the rootfs and drops the execute bit on copied binaries.
# RUN if [ -f /usr/bin/jq ]; then chmod +x /usr/bin/jq; fi 


RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
/kairos-init -l debug -s init -m "generic" -t "false" --version "${KAIROS_VERSION}"


