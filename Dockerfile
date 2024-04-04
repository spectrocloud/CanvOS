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

########################### Add any other image customizations here #######################

####  Examples  ####

### To install the nginx package for Ubuntu  ###

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