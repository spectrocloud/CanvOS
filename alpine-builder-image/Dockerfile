FROM us-docker.pkg.dev/palette-images/edge/canvos/alpine:3.20
COPY certs/ca1.crt /usr/local/share/ca-certificates/
COPY certs/ca2.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
