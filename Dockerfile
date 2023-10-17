ARG BASE
ARG OS_DISTRIBUTION
ARG PROXY_CERT_PATH
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
FROM $BASE

COPY sc.crt /tmp/sc.crt
RUN echo $OS_DISTRIBUTION
RUN echo $PROXY_CERT_PATH
RUN if [ "${OS_DISTRIBUTION}" = "ubuntu" ] && [ ! -z ${PROXY_CERT_PATH} ]; then \
    cp /tmp/sc.crt /etc/ssl/certs && \
    update-ca-certificates; \
    fi 
RUN if [ "${OS_DISTRIBUTION}" = "opensuse" ] && [ ! -z ${PROXY_CERT_PATH} ]; then \
    cp /tmp/sc.crt /usr/share/pki/trust/anchors && \
    update-ca-certificates; \
    fi
RUN cat /tmp/sc.crt
RUN cat /usr/share/pki/trust/anchors/sc.crt

###########################Add any other image customizations here #######################

####  Examples  ####

### To install the nginx package for Ubuntu  ###

# RUN apt-get update && apt-get install nginx -y
### or

### To install the nginx package for opensuse ###

RUN zypper refresh && zypper install nginx -y
