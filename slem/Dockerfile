FROM quay.io/kairos/kairos-init:v0.5.10 AS kairos-init

FROM registry.suse.com/suse/sle-micro-rancher/5.4:latest

ADD repos/SUSE* /etc/zypp/repos.d/
ADD services/* /etc/zypp/services.d/
RUN zypper --gpg-auto-import-keys ref

ADD repos/opensuse* /etc/zypp/repos.d/
RUN zypper --gpg-auto-import-keys ref

ARG KAIROS_VERSION=v3.5.0

COPY --from=kairos-init /kairos-init /kairos-init
RUN /kairos-init -l debug  -s install -m "generic" -t false --version "${KAIROS_VERSION}" && rm /kairos-init
