VERSION 0.6
FROM gcr.io/spectro-images-public/alpine:3.16.2

# Variables used in the builds.  Update for ADVANCED use cases only
ARG OS_DISTRIBUTION
ARG OS_VERSION
ARG IMAGE_REGISTRY
ARG IMAGE_REPO=$OS_DISTRIBUTION
ARG K8S_DISTRIBUTION
ARG CUSTOM_TAG
ARG ARCH
ARG PE_VERSION=v4.0.5
ARG SPECTRO_LUET_VERSION=v1.1.4
ARG KAIROS_VERSION=v2.3.2
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.7.11
ARG OSBUILDER_IMAGE=quay.io/kairos/osbuilder-tools:$OSBUILDER_VERSION
ARG K3S_PROVIDER_VERSION=v2.3.2
ARG KUBEADM_PROVIDER_VERSION=v2.3.3
ARG RKE2_PROVIDER_VERSION=v2.3.3
ARG FIPS_ENABLED=false
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy=${HTTP_PROXY}
ARG https_proxy=${HTTPS_PROXY}
ARG PROXY_CERT_PATH
ARG UPDATE_KERNEL=false

ARG ETCD_VERSION="v3.5.5"

IF [ "$OS_DISTRIBUTION" = "ubuntu" ] && [ "$BASE_IMAGE" = "" ]
    ARG BASE_IMAGE_NAME=core-$OS_DISTRIBUTION-$OS_VERSION-lts
    ARG BASE_IMAGE_TAG=core-$OS_DISTRIBUTION-$OS_VERSION-lts:$KAIROS_VERSION
    ARG BASE_IMAGE=$BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$BASE_IMAGE" = "" ]
    ARG BASE_IMAGE_NAME=core-$OS_DISTRIBUTION  
    ARG BASE_IMAGE_TAG=core-$OS_DISTRIBUTION:$KAIROS_VERSION
    ARG BASE_IMAGE=$BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "rhel" ]
    # Check for default value for rhel
    ARG BASE_IMAGE
END

IF [[ "$BASE_IMAGE" =~ "ubuntu-20-lts-arm-nvidia-jetson-agx-orin" ]]
    ARG IS_JETSON=true
END

build-all-images:
    IF $FIPS_ENABLED
        BUILD +build-provider-images-fips
    ELSE
        BUILD  +build-provider-images
    END
    IF [ "$ARCH" = "arm64" ]
       BUILD --platform=linux/arm64 +iso-image
       BUILD --platform=linux/arm64 +iso
    ELSE IF [ "$ARCH" = "amd64" ]
       BUILD --platform=linux/amd64 +iso-image
       BUILD --platform=linux/amd64 +iso
    END

build-provider-images:
   BUILD  +provider-image --K8S_VERSION=1.24.6
   BUILD  +provider-image --K8S_VERSION=1.25.2
   BUILD  +provider-image --K8S_VERSION=1.26.4
   BUILD  +provider-image --K8S_VERSION=1.27.2


build-provider-images-fips:
    IF $FIPS_ENABLED  && [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
       BUILD  +provider-image --K8S_VERSION=1.24.13
       BUILD  +provider-image --K8S_VERSION=1.25.9
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
    ELSE IF $FIPS_ENABLED  && [ "$K8S_DISTRIBUTION" = "rke2" ]
       BUILD  +provider-image --K8S_VERSION=1.24.6
       BUILD  +provider-image --K8S_VERSION=1.25.2
       BUILD  +provider-image --K8S_VERSION=1.25.0
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
    ELSE
       BUILD  +provider-image --K8S_VERSION=1.24.6
       BUILD  +provider-image --K8S_VERSION=1.25.2
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
    END

download-etcdctl:
    FROM alpine
    ARG TARGETOS
    ARG TARGETARCH
    RUN apk add curl
    RUN curl  --retry 5 -Ls https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz | tar -xvzf - --strip-components=1 etcd-${ETCD_VERSION}-linux-${TARGETARCH}/etcdctl && \
            chmod +x etcdctl
    SAVE ARTIFACT etcdctl

iso-image-rootfs:
    FROM --platform=linux/${ARCH} +iso-image
    SAVE ARTIFACT --keep-own /. rootfs

iso:
    ARG ISO_NAME=installer
    WORKDIR /build
    COPY --platform=linux/${ARCH} (+build-iso/  --ISO_NAME=$ISO_NAME) .
    SAVE ARTIFACT /build/* AS LOCAL ./build/

build-iso:
    ARG ISO_NAME

    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    ENV ISO_NAME=${ISO_NAME}
    COPY overlay/files-iso/ /overlay/
    COPY --if-exists user-data /overlay/files-iso/config.yaml
    COPY --if-exists content-*/*.zst /overlay/opt/spectrocloud/content/
    WORKDIR /build
    COPY --platform=linux/${ARCH} --keep-own +iso-image-rootfs/rootfs /build/image
    IF [ "$ARCH" = "arm64" ]
       RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay  dir:/build/image --debug  --output /iso/ --arch $ARCH
    ELSE IF [ "$ARCH" = "amd64" ]
       RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay  dir:/build/image --debug  --output /iso/ --arch x86_64
    END
    WORKDIR /iso
    RUN sha256sum $ISO_NAME.iso > $ISO_NAME.iso.sha256
    SAVE ARTIFACT /iso/*

# Used to create the provider images.  The --K8S_VERSION will be passed in the earthly build
provider-image:   
    FROM --platform=linux/${ARCH} +base-image
    # added PROVIDER_K8S_VERSION to fix missing image in ghcr.io/kairos-io/provider-*
    ARG K8S_VERSION=1.26.4
    ARG IMAGE_REPO
    ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPO:$K8S_DISTRIBUTION-$K8S_VERSION-$PE_VERSION-$CUSTOM_TAG

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ] || [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    COPY  --platform=linux/${ARCH} +kairos-provider-image/ /
    COPY +stylus-image/etc/elemental/config.yaml /etc/elemental/config.yaml
    COPY +stylus-image/etc/kairos/branding /etc/kairos/branding
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        RUN luet install -y container-runtime/containerd
    END

    IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
       RUN luet install -y container-runtime/containerd-fips
    END

    RUN luet install -y  k8s/$K8S_DISTRIBUTION@$BASE_K8S_VERSION && luet cleanup
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

    COPY (+download-etcdctl/etcdctl) /usr/bin/

    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id

    SAVE IMAGE --push $IMAGE_PATH

stylus-image:
     IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG STYLUS_BASE=gcr.io/spectro-dev-public/stylus-framework-fips-linux-$ARCH:$PE_VERSION
     ELSE
        ARG STYLUS_BASE=gcr.io/spectro-dev-public/stylus-framework-linux-$ARCH:$PE_VERSION
     END
    FROM $STYLUS_BASE
    SAVE ARTIFACT ./*
    SAVE ARTIFACT /etc/kairos/branding
    SAVE ARTIFACT /etc/elemental/config.yaml

kairos-provider-image:
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG PROVIDER_BASE=gcr.io/spectro-images-public/kairos-io/provider-kubeadm:$KUBEADM_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG PROVIDER_BASE=gcr.io/spectro-images-public/kairos-io/provider-kubeadm-fips:$KUBEADM_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG PROVIDER_BASE=gcr.io/spectro-images-public/kairos-io/provider-k3s:$K3S_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ] && $FIPS_ENABLED
        ARG PROVIDER_BASE=gcr.io/spectro-images-public/kairos-io/provider-rke2-fips:$RKE2_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
         ARG PROVIDER_BASE=gcr.io/spectro-images-public/kairos-io/provider-rke2:$RKE2_PROVIDER_VERSION
    END
    FROM --platform=linux/${ARCH} $PROVIDER_BASE
    SAVE ARTIFACT ./*

# base build image used to create the base image for all other image types
base-image:
    FROM DOCKERFILE --build-arg BASE=$BASE_IMAGE .

#    IF $IS_JETSON
#        COPY mount.yaml /system/oem/mount.yaml
#    END
   IF [ "$IS_JETSON" = "true" ]
       COPY mount.yaml /system/oem/mount.yaml
   END

    IF [ "$ARCH" = "arm64" ]
        RUN  mkdir -p /etc/luet/repos.conf.d && \
          SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo-arm  --priority 1 -y && \
          luet repo update
    ELSE IF [ "$ARCH" = "amd64" ]
        RUN  mkdir -p /etc/luet/repos.conf.d && \
          SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
          luet repo update
    END

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ] || [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    IF [ "$OS_DISTRIBUTION" = "ubuntu" ] &&  [ "$ARCH" = "amd64" ]
        RUN apt update && \
            apt install --no-install-recommends zstd vim -y
        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /etc/ssl/certs
            RUN  update-ca-certificates
        END
        IF [ "$UPDATE_KERNEL" = "false" ]
            RUN if dpkg -l linux-image-generic-hwe-20.04 > /dev/null; then apt-mark hold linux-image-generic-hwe-20.04; fi && \
                if dpkg -l linux-image-generic-hwe-22.04 > /dev/null; then apt-mark hold linux-image-generic-hwe-22.04; fi && \
                if dpkg -l linux-image-generic > /dev/null; then apt-mark hold linux-image-generic linux-headers-generic linux-generic; fi
        END
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
    ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$ARCH" = "amd64" ]
        IF [ "$UPDATE_KERNEL" = "false" ]
            RUN zypper al kernel-de*
        END

        RUN zypper refresh && \
           zypper update -y

           IF [ -e "/usr/bin/dracut" ]
             RUN --no-cache kernel=$(ls /lib/modules | tail -n1) && depmod -a "${kernel}"
             RUN --no-cache kernel=$(ls /lib/modules | tail -n1) && dracut -f "/boot/initrd-${kernel}" "${kernel}" && ln -sf "initrd-${kernel}" /boot/initrd
           END
            # zypper up kernel-default && \
            # zypper purge-kernels && \
        RUN zypper install -y zstd vim
        RUN zypper cc && \
            zypper clean
    END

    IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
        RUN zypper install -y apparmor-parser apparmor-profiles
        RUN zypper cc && \
            zypper clean
    END

    IF [ "$ARCH" = "arm64" ]
        RUN mkdir -p /etc/luet/repos.conf.d && luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo-arm --priority 1 -y && luet repo update
    ELSE IF [ "$ARCH" = "amd64" ]
        RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
        luet repo update
    END

    DO +OSRELEASE --OS_VERSION=$KAIROS_VERSION

    RUN rm -rf /var/cache/* && \
        journalctl --vacuum-size=1K && \
        rm -rf /etc/machine-id && \
        rm -rf /var/lib/dbus/machine-id
    RUN touch /etc/machine-id && \ 
        chmod 444 /etc/machine-id
    RUN rm /tmp/* -rf

    # Ensure SElinux gets disabled
    RUN if grep "security=selinux" /etc/cos/bootargs.cfg > /dev/null; then sed -i 's/security=selinux //g' /etc/cos/bootargs.cfg; fi &&\
        if grep "selinux=1" /etc/cos/bootargs.cfg > /dev/null; then sed -i 's/selinux=1/selinux=0/g' /etc/cos/bootargs.cfg; fi

# Used to build the installer image.  The installer ISO will be created from this.
iso-image:
    FROM --platform=linux/${ARCH} +base-image
    COPY --platform=linux/${ARCH} +stylus-image/ /
    COPY overlay/files/ /
    
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id
    SAVE IMAGE palette-installer-image:$PE_VERSION-$CUSTOM_TAG


OSRELEASE:
    COMMAND
    ARG OS_ID=${OS_DISTRIBUTION}
    ARG OS_VERSION
    ARG OS_LABEL=latest
    ARG VARIANT=${OS_DISTRIBUTION}
    ARG FLAVOR=${OS_DISTRIBUTION}
    ARG BUG_REPORT_URL=https://github.com/spectrocloud/CanvOS/issues
    ARG HOME_URL=https://github.com/spectrocloud/CanvOS
    ARG OS_REPO=spectrocloud/CanvOS
    ARG OS_NAME=kairos-core-${OS_DISTRIBUTION}

    # update OS-release file
    RUN sed -i -n '/KAIROS_/!p' /etc/os-release
    RUN envsubst >>/etc/os-release </usr/lib/os-release.tmpl
