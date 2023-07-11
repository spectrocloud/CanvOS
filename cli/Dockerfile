# FROM golang:1.20.6-alpine3.18 as builder

# LABEL org.opencontainers.image.source="http://spectrocloud/CanvOS"
# LABEL org.opencontainers.image.description "A tool to help you create Edge artifacts."

# ARG VERSION

# ADD ./ /source
# RUN cd /source && \
# adduser -H -u 1002 -D appuser appuser && \
# go build -ldflags="-X 'spectrocloud.com/specrocloud.com/internal.Version=${VERSION}'" -o canvos -v

FROM alpine:latest

COPY canvos /usr/bin/canvos

# COPY --from=builder /etc/passwd /etc/passwd
# COPY --from=builder /etc/group /etc/group
# COPY --from=builder --chown=appuser:appuser  /source/canvos /usr/bin/

RUN apk -U upgrade && apk add bash jq git --no-cache 
# USER appuser

ENTRYPOINT ["/usr/bin/canvos"]