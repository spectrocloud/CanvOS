#!/bin/bash -x

set -xe
source variables.env
KAIROS_VERSION="${KAIROS_VERSION:-v1.5.0}"
# OS_FLAVOR="ubuntu-lts-22"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-ttl.sh}"
SPECTRO_VERSION="${SPECTRO_VERSION:-v3.3.3}"
SPECTRO_LUET_VERSION="${SPECTRO_LUET_VERSION:-v1.0.3}"
### Base Image Settings (Do Not modify accept for advanced Use Cases) ###
#########################################################################
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"
### Base Image Settings User Defined(Do Not modify accept for advanced Use Cases)
INSTALLER_IMAGE=${IMAGE_REPOSITORY}/${ISO_IMAGE_NAME}:${SPECTRO_VERSION}
ISO_IMAGE_ID=ttl.sh/${ISO_IMAGE_NAME}:${SPECTRO_VERSION}
USER_DATA_FILE="${USER_DATA_FILE:-user-data.yaml}"
CONTENT_BUNDLE="${CONTENT_BUNDLE:-content_bundle.tar}"
### Build Image Information
BUILD_IMAGE_TAG=build
# DOCKERFILE_BUILD_IMAGE=./base_images/Dockerfile.${OS_FLAVOR}-${K8S_FLAVOR}
DOCKERFILE_BUILD_IMAGE=./base_images/Dockerfile.$1
# Check for content or user-data file
if [ -f $USER_DATA_FILE ]; then
 cp $USER_DATA_FILE overlay/files-iso/config.yaml
fi

if [ -f $CONTENT_BUNDLE ]; then
  zstd -19 -T0 -o overlay/files-iso/opt/spectrocloud/content/spectro-content.tar.zst $CONTENT_BUNDLE
fi
# Set Package Variable in Dockerfile for specific OS Flavor
if [[ $OS_FLAVOR == ubuntu* ]]; then
  PACKAGE_VARIABLE="apt"
elif [ $OS_FLAVOR == "opensuse-leap" ]; then
  PACKAGE_VARIABLE="zypper"
fi

### Identify correct tag based on inputs
if [ "$K8S_FLAVOR" == "rke2" ]; then
  K8S_FLAVOR_TAG="-rke2r1"
  K8S_PROVIDER_VERSION="v1.2.3"
elif [ "$K8S_FLAVOR" == "k3s" ]; then
  K8S_FLAVOR_TAG="-k3s1"
  K8S_PROVIDER_VERSION="v1.1.3"
elif [ "$K8S_FLAVOR" == "kubeadm" ]; then
  K8S_FLAVOR_TAG=""
  K8S_PROVIDER_VERSION="v1.1.8"
fi

# Create Build Image
echo "Building Build image $DOCKERFILE_BUILD_IMAGE"
docker build --build-arg SPECTRO_VERSION=$SPECTRO_VERSION \
    --build-arg SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION \
    --build-arg KAIROS_VERSION=$KAIROS_VERSION \
    --build-arg OS_FLAVOR=$OS_FLAVOR \
    --build-arg IMAGE_REPOSITORY=$IMAGE_REPOSITORY \
    --build-arg K8S_FLAVOR=$K8S_FLAVOR \
    --build-arg K8S_FLAVOR_TAG=$K8S_FLAVOR_TAG \
    --build-arg K8S_PROVIDER_VERSION=$K8S_PROVIDER_VERSION \
    --build-arg PACKAGE_VARIABLE=$PACKAGE_VARIABLE \
    -t $BUILD_IMAGE_TAG -f $DOCKERFILE_BUILD_IMAGE .

#Create Installer Image to be used in ISO
echo "Building Installer image $INSTALLER_IMAGE"
docker build --build-arg BUILD_IMAGE=$BUILD_IMAGE_TAG \
    --build-arg PACKAGE_VARIABLE=$PACKAGE_VARIABLE \
    -t $INSTALLER_IMAGE -f ./Dockerfile .
docker tag $INSTALLER_IMAGE $ISO_IMAGE_ID
docker run -v $PWD:/cOS \
            -v /var/run/docker.sock:/var/run/docker.sock \
             -i --rm quay.io/kairos/osbuilder-tools:v0.3.3 \
             --name "${ISO_IMAGE_NAME}-${SPECTRO_VERSION}" \
             --debug build-iso --date=false $ISO_IMAGE_ID \
             --local --overlay-iso /cOS/overlay/files-iso  \
             --output /cOS/
