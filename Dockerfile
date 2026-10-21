ARG BASE
FROM $BASE

ARG OS_DISTRIBUTION
ARG PROXY_CERT_PATH
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

RUN mkdir -p /certs
COPY certs/ /certs/
RUN if [ "${OS_DISTRIBUTION}" = "ubuntu" ]; then \
    cp -a /certs/. /usr/local/share/ca-certificates/ && \
    update-ca-certificates; \
    fi
RUN if [ "${OS_DISTRIBUTION}" = "opensuse-leap" ]; then \
    cp -a /certs/. /usr/share/pki/trust/anchors/ && \
    update-ca-certificates; \
    fi

RUN if [ "${OS_DISTRIBUTION}" = "rhel" ]; then \
    cp -a /certs/. /etc/pki/ca-trust/source/anchors/ && \
    update-ca-trust; \
    fi
RUN rm -rf /certs

# SHA-256 fingerprints of distrusted roots (bugzilla.mozilla.org/2083449): emSign ECC Root CA - G3,
# emSign Root TLS CA - G3, AAA Certificate Services.
ARG DISTRUSTED_ROOTS="86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b 7dd78d5f4f13459a83dff9abbba62edbaf6f2d102bf257fd712f4d9f2746ed8d d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4"
RUN listed() { case " $DISTRUSTED_ROOTS " in *" $(sha256sum < "$1" | cut -d' ' -f1) "*) return 0;; esac; return 1; }; \
    t=$(mktemp -d); \
    if [ -f /etc/ca-certificates.conf ]; then \
    for c in /usr/share/ca-certificates/mozilla/*.crt; do \
    openssl x509 -in "$c" -outform der -out "$t/c" && listed "$t/c" && sed -i "s|^mozilla/${c##*/}\$|!&|" /etc/ca-certificates.conf; \
    done; \
    update-ca-certificates; \
    mkdir "$t/trusted"; for c in /etc/ssl/certs/*.pem; do openssl x509 -in "$c" -outform der -out "$t/trusted/${c##*/}"; done; \
    elif d=$(ls -d /etc/pki/trust/blacklist /etc/pki/ca-trust/source/blocklist /etc/pki/ca-trust/source/blacklist 2>/dev/null | head -n1); [ -n "$d" ]; then \
    trust extract --format=x509-directory --filter=ca-anchors --purpose=server-auth "$t/anchors"; \
    for c in "$t"/anchors/*; do listed "$c" && cp "$c" "$d/"; done; \
    if [ -d /etc/pki/trust ]; then update-ca-certificates; else update-ca-trust; fi; \
    trust extract --format=x509-directory --filter=ca-anchors --purpose=server-auth "$t/trusted"; \
    fi; \
    for c in "$t"/trusted/*; do [ -f "$c" ] && listed "$c" && { echo "distrusted root is still trusted: ${c##*/}" >&2; exit 1; }; done; \
    rm -rf "$t"

# This file provides the ability to extend or override GPU specifications in the default lookup table
COPY overlay/files/etc/spectrocloud/custom-hardware-specs-lookup.json /etc/spectrocloud/custom-hardware-specs-lookup.json


########################### Add any other image customizations here #######################

####  Examples  ####

### To install the nginx package for Ubuntu  ###

#TODO: Remove the following line. This is only for dev purpose.

# RUN useradd -m kairos && echo "kairos:kairos" | chpasswd
# RUN adduser kairos sudo
# RUN echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# sbctl and mokutil are useful tools to check secure boot status, manage secure boot keys.
# RUN curl -Ls https://github.com/Foxboron/sbctl/releases/download/0.13/sbctl-0.13-linux-amd64.tar.gz | tar -xvzf - && mv sbctl/sbctl /usr/bin/sbctl
# RUN chmod +x /usr/bin/sbctl
# RUN apt-get update && apt-get install -y \
#     mokutil \
#     && apt-get clean

# RUN apt-get update && apt-get install nginx -y

### To install the nginx package for opensuse ###

# RUN zypper refresh && zypper install nginx -y

### To add a custom health script for two-node liveness checks ###

# ADD overlay/files/opt/spectrocloud/bin/check-disk-size.sh /opt/spectrocloud/bin/

### To install wifi prerequisites for Ubuntu ###

# RUN apt-get update && apt-get install wpasupplicant -y && \
#    apt-get update && apt-get install network-manager -y && \
#    apt-get install iputils-ping -y && \
#    mkdir /var/lib/wpa

# Install qemu-guest-agent for Ubuntu (needed for VM guest integration on
# provider images and slim/installer ISOs built via +base-image).
RUN if [ "${OS_DISTRIBUTION}" = "ubuntu" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends qemu-guest-agent && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/*; \
    fi

### To install the DRBD module package for Piraeus pack on Ubuntu  ###

# RUN apt-get update && \
#     DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
#     DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
#       ca-certificates \
#       kmod \
#       gpg \
#       make \
#       # Ubuntu has multiple kernel versions that may be using different gcc versions: use the dkms package to install them all
#       $(apt-get install -s dkms | awk '/^Inst gcc/{print $2}') \
#       patch \
#       diffutils \
#       perl \
#       elfutils \
#       libc-dev \
#       coccinelle \
#       curl && \
#     apt-get clean

# ARG DRBD_VERSION
# ADD https://pkg.linbit.com/downloads/drbd/9/drbd-${DRBD_VERSION}.tar.gz /drbd.tar.gz
# ADD --chmod=0755 https://raw.githubusercontent.com/LINBIT/drbd/master/docker/entry.sh /entry.sh

# ENV LB_HOW compile
# ENTRYPOINT /entry.sh

# Enable cgroup v2 (unified hierarchy) — required for Kubernetes >= 1.31 (deprecated in 1.31, hard-fail in 1.35)
# UKI images use systemd-boot (no bootargs.cfg), so skip when file is absent
RUN if [ -f /etc/cos/bootargs.cfg ] && ! grep -Fq "systemd.unified_cgroup_hierarchy=1" /etc/cos/bootargs.cfg; then \
        sed -i 's|\(set baseCmd="[^"]*\)"|\1 systemd.unified_cgroup_hierarchy=1"|' /etc/cos/bootargs.cfg; \
    fi
