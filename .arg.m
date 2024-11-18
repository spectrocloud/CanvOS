BASE_IMAGE=registry.spectrocloud.dev/kairos-rhel9:9.4-6
SPECTRO_LUET_REPO=us-docker.spectrocloud.dev/palette-images/edge
SPECTRO_PUB_REPO=us-docker.spectrocloud.dev/palette-images
ALPINE_IMG=registry.spectrocloud.dev/alpine:3.20
SPECTRO_THIRD_PARTY_IMAGE=gcr.spectrocloud.dev/spectro-images-public/builders/spectro-third-party:4.5

HTTPS_PROXY=http://infra-proxy.spectrocloud.dev
HTTP_PROXY=http://infra-proxy.spectrocloud.dev
NO_PROXY="*.spectrocloud.dev"
PROXY_CERT_PATH=/root/ca-cert/
OSBUILDER_VERSION=v0.300.3
OSBUILDER_IMAGE=quay.spectrocloud.dev/kairos/osbuilder-tools:$OSBUILDER_VERSION

CUSTOM_TAG=rhel9-4
IMAGE_REGISTRY=registry.spectrocloud.dev
OS_DISTRIBUTION=rhel
IMAGE_REPO=kairos
OS_VERSION=9
K8S_DISTRIBUTION=kubeadm
ISO_NAME=palette-edge-installer
ARCH=amd64
UPDATE_KERNEL=false
CLUSTERCONFIG=spc.tgz
CIS_HARDENING=false
EDGE_CUSTOM_CONFIG=.edge-custom-config.yaml
