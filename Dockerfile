ARG BASE
FROM $BASE

###########################Add any other image customizations here #######################

####  Examples  ####

### To install the nginx package for Ubuntu  ###

#RUN apt-get update && apt-get install nginx -y

### or

### To install the nginx package for opensuse ###

#RUN zypper refresh && zypper install nginx -y

# Add custom health check for two-node liveness

# ADD overlay/files/opt/spectrocloud/bin/check-disk-size.sh /opt/spectrocloud/bin/
