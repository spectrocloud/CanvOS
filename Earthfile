VERSION 0.6
FROM alpine

ARG OS_FLAVOR=ubuntu
ARG OS_VERSION=22
ARG IMAGE_REPOSITORY=3pings
ARG K8S_FLAVOR=k3s


ARG STYLUS_VERSION=v3.3.3
ARG SPECTRO_LUET_VERSION=v1.0.3
ARG KAIROS_VERSION=v1.5.0
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.6.1
ARG OSBUILDER_IMAGE=quay.io/kairos/osbuilder-tools:$OSBUILDER_VERSION


IF [ "$OS_FLAVOR" = "ubuntu" ]

    ARG BASE_IMAGE=$BASE_IMAGE_URL/core-$OS_FLAVOR-$OS_VERSION-lts:$KAIROS_VERSION
ELSE IF [ "$OS_FLAVOR" = "opensuse-leap" ]
    ARG BASE_IMAGE=$BASE_IMAGE_URL/core-$OS_FLAVOR:$KAIROS_VERSION
END
ARG STYLUS_BASE=gcr.io/spectro-dev-public/stylus-framework:$STYLUS_VERSION

elemental:
    FROM $OSBUILDER_IMAGE
    RUN zypper in -y jq docker

stylus:
    FROM $STYLUS_BASE
    SAVE ARTIFACT /opt/spectrocloud/bin/stylus-operator
    SAVE ARTIFACT /opt/spectrocloud/bin/stylus-agent
    SAVE ARTIFACT /opt/spectrocloud/manifests/
    # SAVE ARTIFACT /opt/spectrocloud/charts/*
    SAVE ARTIFACT /etc/systemd/system
    SAVE ARTIFACT /oem/
    SAVE ARTIFACT /opt/spectrocloud/bin/

kairos-provider-image:
    IF [ "$K8S_FLAVOR" = "kubeadm" ]
        ARG PROVIDER_VERSION=v1.1.8
        ARG PROVIDER_BASE=ghcr.io/kairos-io/provider-kubeadm:$PROVIDER_VERSION
    ELSE IF [ "$K8S_FLAVOR" = "k3s" ]
        ARG PROVIDER_VERSION=v1.2.3
        ARG PROVIDER_BASE=ghcr.io/kairos-io/provider-k3s:$PROVIDER_VERSION 
        
    ELSE IF [ "$K8S_FLAVOR" = "rke2" ]
        ARG PROVIDER_VERSION=v1.1.3
        ARG PROVIDER_BASE=ghcr.io/kairos-io/provider-rke2:$PROVIDER_VERSION
    END
    FROM $PROVIDER_BASE
    SAVE ARTIFACT ./*

base-image:
    FROM $BASE_IMAGE
    ARG ARCH=amd64
    ENV ARCH=${ARCH}

    RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
        luet repo add kairos  --type docker --url quay.io/kairos/packages -y && \
        luet repo update

    RUN luet install -y system/elemental-cli && luet cleanup
    
    IF [ "$OS_FLAVOR" = "ubuntu-20-lts" ] || [ "$OS_FLAVOR" = "ubuntu-22-lts" ]

        RUN apt update && apt install zstd -y && apt upgrade -y
        RUN kernel=$(ls /boot/vmlinuz-* | head -n1) && \
            ln -sf "${kernel#/boot/}" /boot/vmlinuz
        RUN kernel=$(ls /lib/modules | head -n1) && \
            dracut -f "/boot/initrd-${kernel}" "${kernel}" && \
            ln -sf "initrd-${kernel}" /boot/initrd
        RUN kernel=$(ls /lib/modules | head -n1) && depmod -a "${kernel}"
        RUN rm -rf /var/cache/* \
            && rm /tmp/* -rf \
            && apt clean \
            && apt autoremove \
            && journalctl --vacuum-size=1K \
            && rm -rf /var/lib/dbus/machine-id
    ELSE IF [ "$OS_FLAVOR" = "opensuse-leap" ]
        RUN zypper refresh \
            && zypper update \
            && zypper install -y zstd \
            && zypper cc \
            && zypper clean -a \
            && zypper remove --clean-deps \
            && mkinitrd
    END

installer-image:
    FROM +base-image
    
    COPY +stylus/stylus-operator /opt/spectrocloud/bin/stylus-operator
    COPY +stylus/stylus-agent /opt/spectrocloud/bin/stylus-agent
    COPY +stylus/manifests /opt/spectrocloud/manifests/
    # COPY +stylus/charts/ /opt/spectrocloud/charts/
    COPY +stylus/system /etc/systemd/system
    COPY +stylus/oem/ /oem/
    COPY +stylus/bin/ /opt/spectrocloud/bin/

    COPY overlay/files-iso/ /
    COPY --if-exists user-data /overlay/files-iso/config.yaml
    COPY --if-exists content /overlay/files-iso/opt/spectrocloud/content/
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
    
    SAVE IMAGE 3pings/installer:3.3.3-u


provider-image:
    ARG K8S_VERSION=1.25.2
    FROM +base-image

    IF [ "$K8S_FLAVOR" = "kubeadm" ]
        ARG BASE_K8S_VERSION=$VERSION
    ELSE IF [ "$K8S_FLAVOR" = "k3s" ]
        ARG K8S_FLAVOR_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_FLAVOR_TAG
        
    ELSE IF [ "$K8S_FLAVOR" = "rke2" ]
        ARG K8S_FLAVOR_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_FLAVOR_TAG
    END
    COPY +kairos-provider-image/ /
    RUN luet install -y  k8s/$K8S_FLAVOR@$BASE_K8S_VERSION && luet cleanup
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

    IF [ "$OS_FLAVOR" = "ubuntu" ]
        ENV OS_ID=$OS_FLAVOR
        ENV OS_VERSION=$OS_VERSION.04
        ENV OS_NAME=core-$OS_FLAVOR-$OS_VERSION-lts-$K8S_FLAVOR_TAG:$STYLUS_VERSION
        ENV OS_REPO=$IMAGE_REPOSITORY
        ENV OS_LABEL=$KAIROS_VERSION_$K8S_VERSION_$SPECTRO_VERSION
        RUN envsubst >/etc/os-release </usr/lib/os-release.tmpl
    ELSE IF [ "$OS_FLAVOR" = "opensuse-leap" ]
        ENV OS_ID=$OS_FLAVOR
        ENV OS_VERSION=15.4
        ENV OS_NAME=core-$OS_FLAVOR-$K8S_FLAVOR_TAG:$STYLUS_VERSION
        ENV OS_REPO=$IMAGE_REPOSITORY
        ENV OS_LABEL=$KAIROS_VERSION_$K8S_VERSION_$SPECTRO_VERSION
        RUN envsubst >/etc/os-release </usr/lib/os-release.tmpl
    END

    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id
    
    SAVE IMAGE $IMAGE_REPOSITORY/${OS_FLAVOR}:${K8S_VERSION}-${STYLUS_VERSION}


# iso:
#     ARG OSBUILDER_IMAGE
#     ARG ISO_NAME=installer
#     ARG IMG=docker:3pings/installer:3.3.3
#     ARG overlay=overlay/files-iso
#     FROM $OSBUILDER_IMAGE
#     WORKDIR /build
#     COPY . ./
#     COPY --keep-own +image-rootfs/rootfs /build/image
#     RUN /entrypoint.sh --name $ISO_NAME --debug build-iso --squash-no-compression --date=false dir:/build/image --overlay-iso /build/${overlay} --output /build/
#     SAVE ARTIFACT /build/$ISO_NAME.iso kairos.iso AS LOCAL build/$ISO_NAME.iso
#     SAVE ARTIFACT /build/$ISO_NAME.iso.sha256 kairos.iso.sha256 AS LOCAL build/$ISO_NAME.iso.sha256
build-iso:
    ARG ISO_NAME=installer
    ARG BUILDPLATFORM

    FROM +elemental
    ENV ISO_NAME=${ISO_NAME}

    COPY overlay/files-iso/ /overlay/

    WITH DOCKER --allow-privileged --load iso-image=(+installer-image --platform=$BUILDPLATFORM)
            RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay --local "iso-image:latest" --output /build/
    END

    WORKDIR /build
    RUN sha256sum $ISO_NAME.iso > $ISO_NAME.iso.sha256

    SAVE ARTIFACT /build/* AS LOCAL ./build/
build-provider-images:
    FROM alpine
    BUILD +provider-image --K8S_VERSION=1.24.6 --K8S_VERSION=1.25.2

build-all-images:
    FROM alpine
    BUILD +build-provider-images 
    BUILD +build-iso