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



### To install the DRBD module package for Piraeus pack on Ubuntu  ###

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends -y \
      ca-certificates \
      kmod \
      gpg \
      make \
      # Ubuntu has multiple kernel versions that may be using different gcc versions: use the dkms package to install them all
      $(apt-get install -s dkms | awk '/^Inst gcc/{print $2}') \
      patch \
      diffutils \
      perl \
      elfutils \
      libc-dev \
      coccinelle \
      curl && \
    apt-get clean

ARG DRBD_VERSION
ADD https://pkg.linbit.com/downloads/drbd/9/drbd-${DRBD_VERSION}.tar.gz /drbd.tar.gz
ADD --chmod=0755 https://raw.githubusercontent.com/LINBIT/drbd/master/docker/entry.sh /entry.sh

ENV LB_HOW compile
ENTRYPOINT /entry.sh