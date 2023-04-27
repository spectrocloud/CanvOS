FROM alpine

###########################Add any other image customizations here #######################

    RUN apt update && apt install nginx
#Examples
# To install the nginx package from ubuntu or opensuse repos
#RUN zypper refresh && zypper install nginx
# or
#RUN apt-get update && apt-get install nginx
# RUN apt update && $PACKAGE_VARIABLE install -y nginx
