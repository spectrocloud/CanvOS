FROM quay.io/kairos/kairos-init:v0.16.1 AS kairos-init

FROM registry.suse.com/suse/sle-micro-rancher/5.5:latest

ARG KAIROS_VERSION=v4.1.2
COPY --from=kairos-init /kairos-init /kairos-init

RUN /kairos-init -l debug -m "generic" -t false --version "${KAIROS_VERSION}" && rm /kairos-init
