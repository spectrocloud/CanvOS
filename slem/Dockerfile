ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:v0.8.12
FROM ${KAIROS_INIT_IMAGE} AS kairos-init

FROM registry.suse.com/suse/sle-micro-rancher/5.4:latest

ARG KAIROS_VERSION=v4.0.3
ARG TRUSTED_BOOT=false
COPY --from=kairos-init /kairos-init /kairos-init

RUN /kairos-init -l debug -m "generic" -t false --version "${KAIROS_VERSION}" && rm /kairos-init