#!/bin/bash

set -ex

REGISTRATION_CODE=$1
mkdir /var/slem
cd /var/slem
mkdir repos
mkdir services
cd repos/
mkdir SUSE
mkdir opensuse
cd SUSE
cp /etc/zypp/repos.d/SUSE*.repo .
cd ../../services/
cp /etc/zypp/services.d/*.service .
cd ../repos/opensuse/
cat > opensuse-oss.repo <<EOF
[opensuse-oss]
enabled=1
autorefresh=0
baseurl=http://download.opensuse.org/distribution/leap/15.5/repo/oss/
EOF
cd ../..
SUSEConnect -r $REGISTRATION_CODE
systemctl restart docker
transactional-update -n pkg install docker
transactional-update -n register -p PackageHub/15.4/x86_64
docker build -t slem-base-image:v243 .

