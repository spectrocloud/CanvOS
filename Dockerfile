ARG BASE
FROM $BASE

###########################Add any other image customizations here #######################

#Examples
# To install the nginx package from ubuntu or opensuse repos
#RUN zypper refresh && zypper install nginx
# or
#RUN apt-get update && apt-get install nginx
# RUN apt update && $PACKAGE_VARIABLE install -y nginx