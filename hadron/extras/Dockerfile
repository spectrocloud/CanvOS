ARG HADRON_VERSION=v0.3.3-rc2
ARG JQ_VERSION=1.8.1
ARG ARCH=amd64

FROM ghcr.io/kairos-io/hadron-toolchain:${HADRON_VERSION} AS builder

# Install jq
ARG JQ_VERSION
ARG ARCH
WORKDIR /output
RUN mkdir -p /output/usr/bin && \
    curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${ARCH}" -o /output/usr/bin/jq && \
    chmod +x /output/usr/bin/jq

# Install rsyslog


FROM scratch AS export
COPY --from=builder /output /
