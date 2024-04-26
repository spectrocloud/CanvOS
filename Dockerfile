ARG BASE
FROM $BASE

ARG OS_DISTRIBUTION
ARG PROXY_CERT_PATH
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

COPY sc.cr[t] /tmp/sc.crt
RUN if [ "${OS_DISTRIBUTION}" = "ubuntu" ] && [ "${PROXY_CERT_PATH}" != "" ]; then \
    cp /tmp/sc.crt /etc/ssl/certs && \
    update-ca-certificates; \
    fi 
RUN if [ "${OS_DISTRIBUTION}" = "opensuse-leap" ] && [ "${PROXY_CERT_PATH}" != "" ]; then \
    cp /tmp/sc.crt /usr/share/pki/trust/anchors && \
    update-ca-certificates; \
    fi

###########################Add any other image customizations here #######################

####  Examples  ####

### To install the nginx package for Ubuntu  ###

#TODO: Remove the following line. This is only for dev purpose.
# RUN useradd -m kairos && echo "kairos:kairos" | chpasswd
# RUN adduser kairos sudo
# RUN echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# sbctl and mokutil are useful tools to check secure boot status, manage secure boot keys.
RUN curl -Ls https://github.com/Foxboron/sbctl/releases/download/0.13/sbctl-0.13-linux-amd64.tar.gz | tar -xvzf - && mv sbctl/sbctl /usr/bin/sbctl
RUN chmod +x /usr/bin/sbctl
RUN apt-get update && apt-get install -y \
    mokutil \
    && apt-get clean

# RUN apt-get update && apt-get install nginx -y
### or

### To install the nginx package for opensuse ###

# RUN zypper refresh && zypper install nginx -y
