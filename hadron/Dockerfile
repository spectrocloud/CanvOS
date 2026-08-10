ARG HADRON_VERSION=v0.5.1
ARG KAIROS_INIT_VERSION=v0.16.3
ARG FIPS=false
ARG IS_UKI=false

ARG MODULES_IMAGE=us-east1-docker.pkg.dev/spectro-images/dev/arun/hadron/modules:${HADRON_VERSION}

FROM quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION} AS kairos-init

FROM ${MODULES_IMAGE} AS modules

FROM ghcr.io/kairos-io/hadron:${HADRON_VERSION}         AS base-fips-false-uki-false
FROM ghcr.io/kairos-io/hadron-fips:${HADRON_VERSION}    AS base-fips-true-uki-false
FROM ghcr.io/kairos-io/hadron-trusted:${HADRON_VERSION} AS base-fips-false-uki-true
# base-fips-true-uki-true intentionally omitted: FIPS and UKI cannot be combined.

FROM base-fips-${FIPS}-uki-${IS_UKI} AS base-kairos
ARG KAIROS_VERSION=v4.1.2
ARG FIPS=false
ARG IS_UKI=false

# The base image ships /usr/sbin/ip and /sbin/ip as symlinks into /bin/busybox. 
# Drop them so the modules COPY lands the real iproute2 `ip` as a regular file rather than being resolved by buildkit into
# /bin/busybox and overwriting the multi-call binary itself.
RUN rm -f /usr/sbin/ip /sbin/ip

COPY --from=modules / /

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    FIPS_FLAG=$([ "${FIPS}" = "true" ] && echo "--fips" || true) && \
    /kairos-init -l debug -s install -m "generic" -t "${IS_UKI}" --version "${KAIROS_VERSION}" ${FIPS_FLAG}

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    FIPS_FLAG=$([ "${FIPS}" = "true" ] && echo "--fips" || true) && \
    /kairos-init -l debug -s init -m "generic" -t "${IS_UKI}" --version "${KAIROS_VERSION}" ${FIPS_FLAG}
