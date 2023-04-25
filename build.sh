#!/bin/bash -x

set -xe
source variables.env

### Base Image Settings (Do Not modify accept for advanced Use Cases) ###
#########################################################################
SPECTRO_VERSION="${SPECTRO_VERSION:-v3.3.3}"
SPECTRO_LUET_VERSION="${SPECTRO_LUET_VERSION:-v1.0.3}"
KAIROS_VERSION="${KAIROS_VERSION:-v1.5.0}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

### Base Image Settings User Defined(Do Not modify accept for advanced Use Cases)

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-ttl.sh}"
INSTALLER_IMAGE=${IMAGE_REPOSITORY}/${ISO_IMAGE_NAME}:${SPECTRO_VERSION}
ISO_IMAGE_ID=ttl.sh/${ISO_IMAGE_NAME}:${SPECTRO_VERSION}
USER_DATA_FILE="${USER_DATA_FILE:-user-data.yaml}"
CONTENT_BUNDLE="${CONTENT_BUNDLE:-content_bundle.tar}"



### Build Image Information
BUILD_IMAGE_TAG=build
DOCKERFILE_BUILD_IMAGE=./base_images/Dockerfile.${OS_FLAVOR}-${K8S_FLAVOR}

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
if [ "$K8S_FLAVOR" == "rke2" ]; then
  K8S_FLAVOR_TAG="-rke2r1"
elif [ "$K8S_FLAVOR" == "k3s" ]; then
  K8S_FLAVOR_TAG="-k3s1"
elif [ "$K8S_FLAVOR" == "kubeadm" ]; then
  K8S_FLAVOR_TAG=""
fi

# Create Build Image
echo "Building Build image $DOCKERFILE_BUILD_IMAGE"
docker build --build-arg SPECTRO_VERSION=$SPECTRO_VERSION \
    --build-arg SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION \
    -t $BUILD_IMAGE_TAG -f $DOCKERFILE_BUILD_IMAGE .

# Create Installer Image to be used in ISO
echo "Building Installer image $INSTALLER_IMAGE"
docker build --build-arg BUILD_IMAGE=$BUILD_IMAGE_TAG \
    --build-arg PACKAGE_VARIABLE=$PACKAGE_VARIABLE \
    -t $INSTALLER_IMAGE -f ./Dockerfile .

# Create Provider Images
for k8s_version in ${K8S_VERSIONS//,/ }

do

if [ "$K8S_FLAVOR" == "rke2" ]; then
  K8S_FLAVOR_TAG="-rke2r1"
elif [ "$K8S_FLAVOR" == "k3s" ]; then
  K8S_FLAVOR_TAG="-k3s1"
elif [ "$K8S_FLAVOR" == "kubeadm" ]; then
  K8S_FLAVOR_TAG=""
fi
# Change provider image name ex. ttl.sh/core-ubuntu-lts-22-k3s:demo-v1.24.6-k3s1-v3.3.3
PROVIDER_IMAGE_NAME="core-${OS_FLAVOR}-${K8S_FLAVOR}:$CANVOS_ENV-v${k8s_version}${K8S_FLAVOR_TAG}-${SPECTRO_VERSION}"

    IMAGE=${IMAGE_REPOSITORY}/${PROVIDER_IMAGE_NAME}
    docker build --build-arg BUILD_IMAGE=$BUILD_IMAGE_TAG \
                 --build-arg K8S_VERSION=$k8s_version \
                 --build-arg SPECTRO_VERSION=$SPECTRO_VERSION \
                 --build-arg SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION \
                 --build-arg PACKAGE_VARIABLE=$PACKAGE_VARIABLE \
                 -t $IMAGE \
                 -f ./Dockerfile ./
    if [[ "$PUSH_BUILD" == "true" ]]; then
      echo "Pushing image"
      docker push "$IMAGE"
    fi
done

# Remove Old Installer Images from local Image Cache
docker rmi $ISO_IMAGE_ID &>/dev/null || true
# Tag new installer image to normalize name
docker tag $INSTALLER_IMAGE $ISO_IMAGE_ID
# Build Installer ISO
echo "Building $ISO_IMAGE_NAME.iso from $INSTALLER_IMAGE"
docker run -v $PWD:/cOS \
            -v /var/run/docker.sock:/var/run/docker.sock \
             -i --rm quay.io/kairos/osbuilder-tools:v0.3.3 \
             --name "${ISO_IMAGE_NAME}-${SPECTRO_VERSION}" \
             --debug build-iso --date=false $ISO_IMAGE_ID \
             --local --overlay-iso /cOS/overlay/files-iso  \
             --output /cOS/
# Removes installer images from docker
docker rmi $ISO_IMAGE_ID
docker rmi $INSTALLER_IMAGE

# Push Installer Image uncomment if this is needed
# if [[ "$PUSH_BUILD" == "true" ]]; then
#   echo "Pushing image"
#   docker push "$INSTALLER_IMAGE"
# fi

# ISO Push Command Example
# $PUSH_ISO_COMMAND
aws s3 cp ${ISO_IMAGE_NAME}-${SPECTRO_VERSION}.iso s3://edgeforge/images/${ISO_IMAGE_NAME}-${SPECTRO_VERSION}.iso --profile gh-runner

# aws s3 cp $ISO_IMAGE_NAME.iso s3://image.iso

# Clean Local images.  This is used if you are pushing the installer image to something like an S3 bucket for distribution.  Include these if using automated actions.

# rm -f $ISO_IMAGE_NAME.iso
# rm -f $ISO_IMAGE_NAME.iso.sha256
docker rmi $BUILD_IMAGE_TAG
