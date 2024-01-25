#!/bin/bash

if [[ -z "$1" ]]; then
  echo "ERROR : Registration code is empty !"
  echo "Re-run this utility with SUSE Registration code in the args."
  echo "Example : ./build.sh 123456789"
  exit 1
fi
REGISTRATION_CODE=$1

set -ex

mkdir -p /var/slem
yes | cp ./Dockerfile /var/slem
cd /var/slem
mkdir -p repos
mkdir -p services
cd repos/
mkdir -p SUSE
mkdir -p opensuse
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

#SUSEConnect -r $REGISTRATION_CODE
transactional-update register -r $REGISTRATION_CODE
transactional-update -n pkg install docker
#transactional-update -n register -p PackageHub/15.4/x86_64

docker build -t slem-base-image:kairos-v2.4.3_generic .