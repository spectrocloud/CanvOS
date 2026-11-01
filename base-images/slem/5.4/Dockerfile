# kairos-init is tagged with the Kairos version it installs.
ARG KAIROS_VERSION=v4.4.0
ARG KAIROS_INIT_IMAGE=quay.io/kairos/kairos-init:${KAIROS_VERSION}
FROM ${KAIROS_INIT_IMAGE} AS kairos-init

FROM registry.suse.com/suse/sle-micro-rancher/5.4:latest

ARG KAIROS_VERSION
ARG MODEL=generic
COPY --from=kairos-init /kairos-init /kairos-init

RUN /kairos-init -l debug -m "${MODEL}" -t false --version "${KAIROS_VERSION}" && rm /kairos-init

# Mozilla bug 2083449: distrust the roots that chain to the compromised eMudhra intermediates.
# Bind-mounted from the `scripts` build context (bake requires BuildKit).
RUN --mount=type=bind,from=scripts,source=distrust-emudhra-roots.sh,target=/tmp/distrust-emudhra-roots.sh \
    sh /tmp/distrust-emudhra-roots.sh
