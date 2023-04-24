ARG BUILD_IMAGE
FROM ${BUILD_IMAGE}
ARG PACKAGE_VARIABLE
ENV PACKAGE_VARIABLE=${PACKAGE_VARIABLE}


###########################Add any other image customizations here #######################

#Examples
# To install the nginx package from ubuntu or opensuse repos
#RUN zypper refresh && zypper install nginx
# or
#RUN apt-get update && apt-get install nginx
# RUN apt update && $PACKAGE_VARIABLE install -y nginx
##########################################################################################



RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

# Clear cache and cleaning image for usage
RUN rm -rf /var/cache/*
RUN rm /tmp/* -rf
RUN $PACKAGE_VARIABLE clean
RUN journalctl --vacuum-size=1K
RUN rm -rf /var/lib/dbus/machine-id