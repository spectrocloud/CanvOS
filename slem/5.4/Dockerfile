FROM quay.io/kairos/kairos-init:v0.17.1 AS kairos-init

FROM registry.suse.com/suse/sle-micro-rancher/5.4:latest

ARG KAIROS_VERSION=v4.1.2
COPY --from=kairos-init /kairos-init /kairos-init

RUN /kairos-init -l debug -m "generic" -t false --version "${KAIROS_VERSION}" && rm /kairos-init

# Mozilla bug 2083449: distrust the roots that chain to the compromised eMudhra intermediates.
# build.sh copies the script into the build directory.
COPY distrust-emudhra-roots.sh /usr/local/bin/distrust-emudhra-roots.sh
RUN chmod 0755 /usr/local/bin/distrust-emudhra-roots.sh && \
    /usr/local/bin/distrust-emudhra-roots.sh
