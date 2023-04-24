ARG BUILD_IMAGE_TAG
FROM ${BUILD_IMAGE_TAG}

###########################Add any other image customizations here #######################

#Examples
# To install the nginx package from ubuntu or opensuse repos
#RUN zypper refresh && zypper install nginx
# or
#RUN apt-get update && apt-get install nginx
RUN apt-get update && apt-get install -y nginx
##########################################################################################
RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
# Clear cache
RUN rm -rf /var/cache/*
RUN apt-get clean && rm -rf /var/cache/* && journalctl --vacuum-size=1K && rm /etc/machine-id && rm /var/lib/dbus/machine-id && rm /etc/hostname