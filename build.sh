#!/bin/bash -x

set -xe
source .variables.env

### Base Image Settings (Do Not modify accept for advanced Use Cases)
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-ttl.sh}"
SPECTRO_VERSION="${SPECTRO_VERSION:-v3.3.3}"
SPECTRO_LUET_VERSION="${SPECTRO_LUET_VERSION:-v1.0.3}"
KAIROS_VERSION="${KAIROS_VERSION:-v1.5.0}"
INSTALLER_IMAGE=${IMAGE_REPOSITORY}/${ISO_IMAGE_NAME}:${SPECTRO_VERSION}
ISO_IMAGE_ID=ttl.sh/${ISO_IMAGE_NAME}:${SPECTRO_VERSION}
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"
KAIROS_VERSION="${KAIROS_VERSION:-v1.5.0}"

### Build Image Information
BUILD_IMAGE_TAG=build
DOCKERFILE_BUILD_IMAGE=./base_images/Dockerfile.${OS_FLAVOR}-${K8S_FLAVOR}

# Set Package Variable in Dockerfile for specific OS Flavor
if [[ $OS_FLAVOR == ubuntu* ]]; then
  PACKAGE_VARIABLE="apt"
elif [ $OS_FLAVOR == "opensuse-leap" ]; then
  PACKAGE_VARIABLE="zypper"
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
    IMAGE=${IMAGE_REPOSITORY}/core-${OS_FLAVOR}-${K8S_FLAVOR}:$CANVOS_ENV-v${k8s_version}_${SPECTRO_VERSION}
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
docker rmi $ISO_IMAGE_ID || true
# Tag new installer image
docker tag $INSTALLER_IMAGE $ISO_IMAGE_ID
# Build Installer ISO
echo "Building $ISO_IMAGE_NAME.iso from $INSTALLER_IMAGE"
docker run -v $PWD:/cOS \
            -v /var/run/docker.sock:/var/run/docker.sock \
             -i --rm quay.io/kairos/osbuilder-tools:v0.3.3 --name $ISO_IMAGE_NAME \
             --debug build-iso --date=false $ISO_IMAGE_ID --local --overlay-iso /cOS/overlay/files-iso  --output /cOS/
docker rmi $ISO_IMAGE_ID

# # Push Installer Image uncomment if this is needed
# if [[ "$PUSH_BUILD" == "true" ]]; then
#   echo "Pushing image"
#   docker push "$INSTALLER_IMAGE"
# fi

# aws s3 cp $ISO_IMAGE_NAME.iso s3://edgeforge/images/$ISO_IMAGE_NAME-$SPECTRO_VERSION.iso --profile gh-runner
# Clean Local images.  This is used if you are pushing the installer image to something like an S3 bucket for distribution.
rm -f $ISO_IMAGE_NAME.iso
rm -f $ISO_IMAGE_NAME.iso.sha256
docker rmi $BUILD_IMAGE_TAG
