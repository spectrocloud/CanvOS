ARG HADRON_VERSION=v0.4.0
ARG MODULES_IMAGE=us-east1-docker.pkg.dev/spectro-images/dev/arun/hadron/modules:${HADRON_VERSION}
ARG KAIROS_INIT_VERSION=v0.14.4
ARG FIPS=false

FROM quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION} AS kairos-init

FROM ${MODULES_IMAGE} AS modules

FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION} AS base-false
FROM ghcr.io/kairos-io/hadron-fips:${HADRON_VERSION} AS base-true

FROM base-${FIPS} AS base-kairos
ARG KAIROS_VERSION=v4.1.0
ARG FIPS=false

COPY --from=modules / /

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    FIPS_FLAG=$([ "${FIPS}" = "true" ] && echo "--fips" || true) && \
    /kairos-init -l debug -s install -m "generic" -t "false" --version "${KAIROS_VERSION}" ${FIPS_FLAG}

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    FIPS_FLAG=$([ "${FIPS}" = "true" ] && echo "--fips" || true) && \
    /kairos-init -l debug -s init -m "generic" -t "false" --version "${KAIROS_VERSION}" ${FIPS_FLAG}
