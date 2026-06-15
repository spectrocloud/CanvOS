ARG EXTRAS_IMAGE=us-east1-docker.pkg.dev/spectro-images/dev/arun/hadron/extras-modules:v0.3.3-rc2
ARG BASE_IMAGE=ghcr.io/kairos-io/hadron-fips:v0.3.5
ARG KAIROS_INIT_VERSION=v0.14.4


FROM quay.io/kairos/kairos-init:${KAIROS_INIT_VERSION} AS kairos-init

FROM ${EXTRAS_IMAGE} AS extras

FROM ${BASE_IMAGE} AS base-kairos
ARG KAIROS_VERSION=v4.1.0

COPY --from=extras / /

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s install -m "generic" -t "false" --version "${KAIROS_VERSION}" --fips

RUN --mount=type=bind,from=kairos-init,src=/kairos-init,dst=/kairos-init \
    /kairos-init -l debug -s init -m "generic" -t "false" --version "${KAIROS_VERSION}" --fips

# Regenerate the kernel HMAC for the FIPS boot-time integrity self-check.
# kairos-init's init stage (above) rebuilds the initrd and the /boot/vmlinuz +
# /boot/.vmlinuz.hmac symlinks, but leaves /boot/.vmlinuz-<kver>.hmac empty
# (0 bytes). When booted with fips=1, dracut's fips module (fips.sh) reads this
# file as HMAC_SUM_ORIG; an empty value fails the check and dracut aborts with
# "FIPS integrity test failed" / "Refusing to continue", halting boot in the
# initramfs before pivoting to the real root. This MUST be the final build step,
# i.e. after the init stage that re-empties the file, so the stored HMAC matches
# the shipped kernel.
# RUN kver="$(cat /boot/kernel-release 2>/dev/null || ls /lib/modules | sort -V | tail -1)" && \
#     sha512hmac "/boot/vmlinuz-${kver}" | sed "s|  .*/|  /boot/|" > "/boot/.vmlinuz-${kver}.hmac" && \
#     ln -sf "/boot/.vmlinuz-${kver}.hmac" /boot/.vmlinuz.hmac && \
#     test -s "/boot/.vmlinuz-${kver}.hmac" && \
#     echo "kernel HMAC regenerated for ${kver}: $(cat /boot/.vmlinuz-${kver}.hmac)"

# COPY stylus.conf /etc/ssh/sshd_config.d/stylus.conf