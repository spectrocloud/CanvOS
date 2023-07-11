VERSION 0.6
FROM gcr.io/spectro-images-public/alpine:3.16.2

# Variables used in the builds.  Update for ADVANCED use cases only
ARG OS_DISTRIBUTION
ARG OS_VERSION
ARG IMAGE_REGISTRY
ARG IMAGE_REPO=$OS_DISTRIBUTION
ARG K8S_DISTRIBUTION
ARG CUSTOM_TAG
ARG PE_VERSION
ARG SPECTRO_LUET_VERSION=v1.0.4
ARG KAIROS_VERSION=v2.1.3
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.6.1
ARG OSBUILDER_IMAGE=quay.io/kairos/osbuilder-tools:$OSBUILDER_VERSION
ARG K3S_PROVIDER_VERSION=v2.1.3
ARG KUBEADM_PROVIDER_VERSION=v2.1.3
ARG RKE2_PROVIDER_VERSION=v2.1.3
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy=${HTTP_PROXY}
ARG https_proxy=${HTTPS_PROXY}
ARG PROXY_CERT_PATH

IF [ "$OS_DISTRIBUTION" = "ubuntu" ]
    ARG BASE_IMAGE_NAME=core-$OS_DISTRIBUTION-$OS_VERSION-lts
    ARG BASE_IMAGE_TAG=core-$OS_DISTRIBUTION-$OS_VERSION-lts:$KAIROS_VERSION
    ARG BASE_IMAGE=$BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
    ARG BASE_IMAGE_NAME=core-$OS_DISTRIBUTION  
    ARG BASE_IMAGE_TAG=core-$OS_DISTRIBUTION:$KAIROS_VERSION
    ARG BASE_IMAGE=$BASE_IMAGE_URL/$BASE_IMAGE_TAG
END

build-all-images:
    BUILD +build-provider-images
    BUILD +iso

build-provider-images:
    BUILD +provider-image --K8S_VERSION=1.24.6
    BUILD +provider-image --K8S_VERSION=1.25.2

iso-image-rootfs:
    FROM +iso-image
    SAVE ARTIFACT --keep-own /. rootfs

iso:
    ARG ISO_NAME=installer
    WORKDIR /build
    COPY (+build-iso/  --ISO_NAME=$ISO_NAME) .
    SAVE ARTIFACT /build/* AS LOCAL ./build/

build-iso:
    ARG ISO_NAME
    ARG BUILDPLATFORM
    FROM $OSBUILDER_IMAGE
    ENV ISO_NAME=${ISO_NAME}
    COPY overlay/files-iso/ /overlay/
    COPY --if-exists user-data /overlay/files-iso/config.yaml
    COPY --if-exists content-*/*.zst /overlay/opt/spectrocloud/content/
    WORKDIR /build
    COPY --keep-own +iso-image-rootfs/rootfs /build/image
    RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay  dir:/build/image --debug  --output /iso/
    WORKDIR /iso
    RUN sha256sum $ISO_NAME.iso > $ISO_NAME.iso.sha256
    SAVE ARTIFACT /iso/*

# Used to create the provider images.  The --K8S_VERSION will be passed in the earthly build
provider-image:
    FROM +base-image
    # added PROVIDER_K8S_VERSION to fix missing image in ghcr.io/kairos-io/provider-*
    ARG K8S_VERSION=1.25.2
    ARG IMAGE_REPO
    ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPO:$K8S_DISTRIBUTION-$K8S_VERSION-$PE_VERSION-$CUSTOM_TAG

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END
    COPY +kairos-provider-image/ /
    COPY +stylus-image/etc/elemental/config.yaml /etc/elemental/config.yaml
    COPY +stylus-image/etc/kairos/branding /etc/kairos/branding
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        RUN luet install -y container-runtime/containerd
    END
    RUN luet install -y  k8s/$K8S_DISTRIBUTION@$BASE_K8S_VERSION && luet cleanup
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id

    SAVE IMAGE --push $IMAGE_PATH

stylus-image:
    ARG STYLUS_BASE=gcr.io/spectro-dev-public/stylus-framework:$PE_VERSION
    FROM $STYLUS_BASE
    SAVE ARTIFACT ./*
    SAVE ARTIFACT /etc/kairos/branding
    SAVE ARTIFACT /etc/elemental/config.yaml

kairos-provider-image:
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG PROVIDER_BASE=ghcr.io/kairos-io/provider-kubeadm:$KUBEADM_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG PROVIDER_BASE=ghcr.io/kairos-io/provider-k3s:$K3S_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG PROVIDER_BASE=ghcr.io/kairos-io/provider-rke2:$RKE2_PROVIDER_VERSION
    END
    FROM $PROVIDER_BASE
    SAVE ARTIFACT ./*

# base build image used to create the base image for all other image types
base-image:
    FROM DOCKERFILE --build-arg BASE=$BASE_IMAGE .
    ARG ARCH=amd64
    ENV ARCH=${ARCH}
    # Add proxy certificate if present
    IF [ ! -z $PROXY_CERT_PATH ]
       COPY $PROXY_CERT_PATH /etc/ssl/certs
       RUN  update-ca-certificates
    END
    RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add kairos -y --type docker --url quay.io/kairos/packages --priority 99 && \
        luet repo update && \
        luet install -y system/elemental-cli && \
        rm /etc/luet/repos.conf.d/* && \
        luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
        luet repo update
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    IF [ "$OS_DISTRIBUTION" = "ubuntu" ]
        RUN apt update && \
            apt install --no-install-recommends zstd vim -y
        RUN apt update && \
            apt upgrade -y
        RUN kernel=$(ls /boot/vmlinuz-* | tail -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
        RUN kernel=$(ls /lib/modules | tail -n1) && \
            dracut -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd
        RUN kernel=$(ls /lib/modules | tail -n1) && \
            depmod -a "${kernel}"
        RUN rm -rf /var/cache/* && \
            apt clean
            
    # IF OS Type is Opensuse
    ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
        RUN zypper refresh && \
            zypper update -y && \
            mkinitrd
            # zypper up kernel-default && \
            # zypper purge-kernels && \
        RUN zypper install -y zstd vim
        RUN zypper cc && \
            zypper clean
            
    END
    RUN rm -rf /var/cache/* && \
        journalctl --vacuum-size=1K && \
        rm -rf /etc/machine-id && \
        rm -rf /var/lib/dbus/machine-id
    RUN touch /etc/machine-id && \ 
        chmod 444 /etc/machine-id
    RUN rm /tmp/* -rf

# Used to build the installer image.  The installer ISO will be created from this.
iso-image:
    FROM +base-image
    COPY +stylus-image/ /
    COPY overlay/files/ /
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id
