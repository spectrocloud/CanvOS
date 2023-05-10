VERSION 0.6
FROM alpine

# Variables used in the builds.  Update for ADVANCED use cases only
ARG OS_DISTRIBUTION
ARG OS_VERSION
ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY=$OS_DISTRIBUTION
ARG K8S_DISTRIBUTION
ARG MY_ENVIRONMENT
ARG PE_VERSION
ARG SPECTRO_LUET_VERSION=v1.0.3
ARG KAIROS_VERSION=v1.5.0
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.6.1
ARG OSBUILDER_IMAGE=quay.io/kairos/osbuilder-tools:$OSBUILDER_VERSION
ARG K3S_PROVIDER_VERSION=v1.2.3
ARG KUBEADM_PROVIDER_VERSION=v1.1.8
ARG RKE2_PROVIDER_VERSION=v1.1.3


IF [ "$OS_DISTRIBUTION" = "ubuntu" ]
    ARG BASE_IMAGE=$BASE_IMAGE_URL/core-$OS_DISTRIBUTION-$OS_VERSION-lts:$KAIROS_VERSION
ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
    ARG BASE_IMAGE=$BASE_IMAGE_URL/core-$OS_DISTRIBUTION:$KAIROS_VERSION
END

build-all-images:
    BUILD +build-provider-images
    BUILD +build-iso

build-provider-images:
    BUILD +provider-image --K8S_VERSION=1.24.6
    BUILD +provider-image --K8S_VERSION=1.25.2

build-iso:
    ARG ISO_NAME
    ARG BUILDPLATFORM

    FROM +elemental
    ENV ISO_NAME=${ISO_NAME}

    COPY overlay/files-iso/ /overlay/
    COPY --if-exists user-data /overlay/files-iso/config.yaml
    COPY --if-exists content /overlay/files-iso/opt/spectrocloud/content/

    WITH DOCKER --allow-privileged --load iso-image=(+installer-image --platform=$BUILDPLATFORM)
            RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay --local "iso-image:latest" --output /build/
    END

    WORKDIR /build
    RUN sha256sum $ISO_NAME.iso > $ISO_NAME.iso.sha256

    SAVE ARTIFACT /build/* AS LOCAL ./build/

# Used to create the provider images.  The --K8S_VERSION will be passed in the earthly build
provider-image:
    FROM +base-image
    # added PROVIDER_K8S_VERSION to fix missing image in ghcr.io/kairos-io/provider-*
    ARG PROVIDER_K8S_VERSION=1.25.2
    ARG IMAGE_REPOSITORY
    ARG K8S_VERSION
    ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPOSITORY:$K8S_DISTRIBUTION-$K8S_VERSION-$PE_VERSION-$CUSTOM_TAG


    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG BASE_K8S_VERSION=$VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$PROVIDER_K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$PROVIDER_K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END
    COPY +kairos-provider-image/ /
    COPY overlay/files/ /
    RUN luet install -y  k8s/$K8S_DISTRIBUTION@$BASE_K8S_VERSION && luet cleanup
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id

    
    SAVE IMAGE --push $IMAGE_PATH

elemental:
    FROM $OSBUILDER_IMAGE
    RUN zypper in -y jq docker

stylus:
    ARG STYLUS_BASE=gcr.io/spectro-dev-public/stylus-framework:$PE_VERSION
    FROM $STYLUS_BASE
    SAVE ARTIFACT ./*

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

    RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
        luet repo add kairos  --type docker --url quay.io/kairos/packages -y && \
        luet repo update

    RUN luet install -y system/elemental-cli && \
        luet cleanup
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG BASE_K8S_VERSION=$VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    IF [ "$OS_DISTRIBUTION" = "ubuntu" ]

        ENV OS_ID=$OS_DISTRIBUTION
        ENV OS_VERSION=$OS_VERSION.04
        ENV OS_NAME=core-$OS_DISTRIBUTION-$OS_VERSION-lts-$K8S_DISTRIBUTION_TAG:$PE_VERSION
        ENV OS_REPO=$IMAGE_REGISTRY
        ENV OS_LABEL=$KAIROS_VERSION_$K8S_VERSION_$SPECTRO_VERSION
        RUN envsubst >/etc/os-release </usr/lib/os-release.tmpl
        RUN apt update && \
            # apt upgrade -y && \
            apt install --no-install-recommends -y zstd vim
        RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
        RUN kernel=$(ls /lib/modules | head -n1) && \
            dracut -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd
        RUN kernel=$(ls /lib/modules | head -n1) && \
            depmod -a "${kernel}"
        RUN rm -rf /var/cache/* && \
            apt clean && \
            rm -rf /var/lib/apt/lists/* && \
            apt autoremove -y && \
            journalctl --vacuum-size=1K && \
            rm -rf /var/lib/dbus/machine-id
    # IF OS Type is Opensuse
    ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
        ENV OS_ID=$OS_DISTRIBUTION
        ENV OS_VERSION=15.4
        ENV OS_NAME=core-$OS_DISTRIBUTION-$K8S_DISTRIBUTION_TAG:$PE_VERSION
        ENV OS_REPO=$IMAGE_REGISTRY
        ENV OS_LABEL=$KAIROS_VERSION_$K8S_VERSION_$SPECTRO_VERSION
        RUN envsubst >/etc/os-release </usr/lib/os-release.tmpl
        RUN zypper refresh && \
            zypper update -y && \
            zypper install -y zstd vim && \
            zypper cc && \
            zypper clean -a && \
            mkinitrd
    END
    RUN rm /tmp/* -rf

    # SAVE ARTIFACT . 

# Used to build the installer image.  The installer ISO will be created from this.
installer-image:
    FROM +base-image
    COPY +stylus/ /
    COPY overlay/files/ /
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
