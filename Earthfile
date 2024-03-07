VERSION 0.6
ARG TARGETOS
ARG TARGETARCH
FROM gcr.io/spectro-images-public/canvos/alpine-cert:v1.0.0

# Variables used in the builds.  Update for ADVANCED use cases only
ARG OS_DISTRIBUTION
ARG OS_VERSION
ARG IMAGE_REGISTRY
ARG IMAGE_REPO=$OS_DISTRIBUTION
ARG K8S_DISTRIBUTION
ARG CUSTOM_TAG
ARG CLUSTERCONFIG
ARG ARCH
ARG PE_VERSION=v4.2.3
ARG SPECTRO_LUET_VERSION=v1.2.3
ARG KAIROS_VERSION=v2.4.3
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.200.4
ARG OSBUILDER_IMAGE=quay.io/kairos/osbuilder-tools:$OSBUILDER_VERSION
ARG K3S_PROVIDER_VERSION=v4.2.1
ARG KUBEADM_PROVIDER_VERSION=v4.2.1
ARG RKE2_PROVIDER_VERSION=v4.1.1
ARG FIPS_ENABLED=false
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy=${HTTP_PROXY}
ARG https_proxy=${HTTPS_PROXY}
ARG no_proxy=${NO_PROXY}
ARG PROXY_CERT_PATH
ARG UPDATE_KERNEL=false
ARG IS_UKI=false

ARG ETCD_VERSION="v3.5.5"

IF [ "$OS_DISTRIBUTION" = "ubuntu" ] && [ "$BASE_IMAGE" = "" ]
    IF [ "$OS_VERSION" == 22 ] || [ "$OS_VERSION" == 20 ]
        ARG BASE_IMAGE_TAG=$OS_DISTRIBUTION:$OS_VERSION.04-core-$ARCH-generic-$KAIROS_VERSION
    ELSE
        ARG BASE_IMAGE_TAG=$OS_DISTRIBUTION:$OS_VERSION-core-$ARCH-generic-$KAIROS_VERSION
    END
    ARG BASE_IMAGE=$BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$BASE_IMAGE" = "" ]
    ARG BASE_IMAGE_TAG=opensuse:leap-$OS_VERSION-core-$ARCH-generic-$KAIROS_VERSION
    ARG BASE_IMAGE=$BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "rhel" ] || [ "$OS_DISTRIBUTION" = "sles" ]
    # Check for default value for rhel
    ARG BASE_IMAGE
END

IF [[ "$BASE_IMAGE" =~ "ubuntu-20-lts-arm-nvidia-jetson-agx-orin" ]]
    ARG IS_JETSON=true
END

IF [ "$FIPS_ENABLED" = "true" ]
    ARG STYLUS_BASE=gcr.io/spectro-images-public/stylus-framework-fips-linux-$ARCH:$PE_VERSION
ELSE
    ARG STYLUS_BASE=gcr.io/spectro-images-public/stylus-framework-linux-$ARCH:$PE_VERSION
END

ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPO:$K8S_DISTRIBUTION-$PE_VERSION


build-all-images:
    IF $FIPS_ENABLED
        BUILD +build-provider-images-fips
    ELSE
        BUILD +build-provider-images
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
    BUILD  +provider-image --K8S_VERSION=1.25.13
    BUILD  +provider-image --K8S_VERSION=1.26.8
    BUILD  +provider-image --K8S_VERSION=1.27.5
    BUILD  +provider-image --K8S_VERSION=1.27.7
    BUILD  +provider-image --K8S_VERSION=1.26.10
    BUILD  +provider-image --K8S_VERSION=1.25.15
    BUILD  +provider-image --K8S_VERSION=1.28.2
    BUILD  +provider-image --K8S_VERSION=1.29.0
    BUILD  +provider-image --K8S_VERSION=1.27.9
    BUILD  +provider-image --K8S_VERSION=1.26.12
    BUILD  +provider-image --K8S_VERSION=1.28.5



build-provider-images-fips:
    IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
       BUILD  +provider-image --K8S_VERSION=1.24.13
       BUILD  +provider-image --K8S_VERSION=1.25.9
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
       BUILD  +provider-image --K8S_VERSION=1.29.0
       BUILD  +provider-image --K8S_VERSION=1.27.9
       BUILD  +provider-image --K8S_VERSION=1.26.12
       BUILD  +provider-image --K8S_VERSION=1.28.5
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
       BUILD  +provider-image --K8S_VERSION=1.24.6
       BUILD  +provider-image --K8S_VERSION=1.25.2
       BUILD  +provider-image --K8S_VERSION=1.25.0
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
       BUILD  +provider-image --K8S_VERSION=1.26.12
       BUILD  +provider-image --K8S_VERSION=1.27.9
       BUILD  +provider-image --K8S_VERSION=1.28.5
       BUILD  +provider-image --K8S_VERSION=1.29.0
    ELSE
       BUILD  +provider-image --K8S_VERSION=1.24.6
       BUILD  +provider-image --K8S_VERSION=1.25.2
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
       BUILD  +provider-image --K8S_VERSION=1.26.12
       BUILD  +provider-image --K8S_VERSION=1.27.9
       BUILD  +provider-image --K8S_VERSION=1.28.5
       BUILD  +provider-image --K8S_VERSION=1.29.0
    END

BASE_ALPINE:
    COMMAND
    IF [ ! -z $PROXY_CERT_PATH ]
        COPY sc.crt /etc/ssl/certs
        RUN  update-ca-certificates
    END
    RUN apk add curl

download-etcdctl:
    DO +BASE_ALPINE
    RUN curl  --retry 5 -Ls https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz | tar -xvzf - --strip-components=1 etcd-${ETCD_VERSION}-linux-${TARGETARCH}/etcdctl && \
            chmod +x etcdctl
    SAVE ARTIFACT etcdctl

iso-image-rootfs:
    FROM --platform=linux/${ARCH} +iso-image
    SAVE ARTIFACT --keep-own /. rootfs

uki-iso:
    ARG ISO_NAME=installer
    WORKDIR /build
    COPY --platform=linux/${ARCH} (+build-uki-iso/  --ISO_NAME=$ISO_NAME) .
    SAVE ARTIFACT /build/* AS LOCAL ./build/

uki-provider-image:
    FROM scratch
    WORKDIR /

    COPY --platform=linux/${ARCH} +trust-boot-unpack/ /trusted-boot
    COPY --platform=linux/${ARCH} +install-k8s/ /k8s
    SAVE IMAGE --push $IMAGE_PATH

trust-boot-unpack:
    COPY +luet/luet /usr/bin/luet
    COPY --platform=linux/${ARCH} +build-provider-trustedboot-image/ /image
    RUN FILE="file:/$(find /image -type f -name "*.tar" | head -n 1)" && \
        luet util unpack $FILE /trusted-boot
    SAVE ARTIFACT /trusted-boot/*

luet:
    FROM quay.io/luet/base:latest
    SAVE ARTIFACT /usr/bin/luet /luet

install-k8s:
    FROM alpine
    COPY +luet/luet /usr/bin/luet
    ARG K8S_VERSION=1.26.4

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ] || [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    WORKDIR /output
    RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
        luet repo update
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        RUN luet install -y container-runtime/containerd
    END

    IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
       RUN luet install -y container-runtime/containerd-fips
    END
    RUN luet install -y k8s/$K8S_DISTRIBUTION@$BASE_K8S_VERSION --system-target /output && luet cleanup
    RUN rm -rf /output/var/cache/*
    SAVE ARTIFACT /output/*

internal-slink:
    FROM alpine
    COPY internal/slink/slink /slink
    RUN chmod +x /slink
    SAVE ARTIFACT /slink

build-uki-iso:
    ARG ISO_NAME

    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    ENV ISO_NAME=${ISO_NAME}
    COPY overlay/files-iso/ /overlay/
    COPY --if-exists user-data /overlay/config.yaml
    IF [ "$IS_UKI" = "true" ]
        COPY --platform=linux/${ARCH} +stylus-image/ /overlay/data/stylus/
    END
    COPY --if-exists content-*/*.zst /overlay/opt/spectrocloud/content/
    #check if clusterconfig is passed in
    IF [ "$CLUSTERCONFIG" != "" ]
        COPY --if-exists "$CLUSTERCONFIG" /overlay/opt/spectrocloud/clusterconfig/spc.tgz
    END

    COPY --if-exists ui.tar /overlay/opt/spectrocloud/emc/
    RUN if [ -f /overlay/opt/spectrocloud/emc/ui.tar ]; then \
        tar -xf /overlay/opt/spectrocloud/emc/ui.tar -C /overlay/opt/spectrocloud/emc && \
        rm -f /overlay/opt/spectrocloud/emc/ui.tar; \
    fi

    WORKDIR /build
    COPY --platform=linux/${ARCH} --keep-own +iso-image-rootfs/rootfs /build/image
    IF [ "$ARCH" = "arm64" ]
       RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay  dir:/build/image --debug  --output /iso/ --arch $ARCH
    ELSE IF [ "$ARCH" = "amd64" ]
       COPY keys /keys
       RUN ls -liah /keys
       RUN mkdir /iso
       RUN enki --config-dir /config build-uki dir:/build/image --cmdline "stylus.registration install-mode" --overlay-iso /overlay --overlay-iso /overlay/data -t iso -d /iso -k /keys
       RUN enki --config-dir /config build-uki dir:/build/image -t uki -d /iso -k /keys --cmdline "stylus.registration install-mode"
       RUN enki --config-dir /config build-uki dir:/build/image -t container -d /iso -k /keys --cmdline "stylus.registration install-mode"
    END
    WORKDIR /iso
    SAVE ARTIFACT /iso/*

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
    #check if clusterconfig is passed in
    IF [ "$CLUSTERCONFIG" != "" ]
        COPY --if-exists "$CLUSTERCONFIG" /overlay/opt/spectrocloud/clusterconfig/spc.tgz
    END



    WORKDIR /build
    COPY --platform=linux/${ARCH} --keep-own +iso-image-rootfs/rootfs /build/image

    COPY --if-exists ui.tar /build/image/opt/spectrocloud/emc/
    RUN if [ -f /build/image/opt/spectrocloud/emc/ui.tar ]; then \
        tar -xf /build/image/opt/spectrocloud/emc/ui.tar -C /build/image/opt/spectrocloud/emc && \
        rm -f /build/image/opt/spectrocloud/emc/ui.tar; \
    fi
    
    IF [ "$ARCH" = "arm64" ]
       RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay  dir:/build/image --debug  --output /iso/ --arch $ARCH
    ELSE IF [ "$ARCH" = "amd64" ]
       RUN /entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay  dir:/build/image --debug  --output /iso/ --arch x86_64
       COPY keys /keys
       RUN ls -liah /keys
       RUN enki --config-dir /config build-uki dir:/build/image --cmdline "stylus.registration install-mode" --overlay-iso /overlay -t iso -d /iso -k /keys
       RUN enki --config-dir /config build-uki dir:/build/image -t uki -d /iso -k /keys --cmdline "stylus.registration install-mode"
       RUN enki --config-dir /config build-uki dir:/build/image -t container -d /iso -k /keys --cmdline "stylus.registration install-mode"
    END
    WORKDIR /iso
    RUN sha256sum $ISO_NAME.iso > $ISO_NAME.iso.sha256
    SAVE ARTIFACT /iso/*

### UKI targets
## Generate UKI keys
## earthly +uki-gen --MY_ORG="ACME Corp"
uki-genkey:
    ARG MY_ORG="ACME Corp"
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    RUN /entrypoint.sh genkey "$MY_ORG" -o /keys
    SAVE ARTIFACT /keys AS LOCAL ./

# Used to create the provider images.  The --K8S_VERSION will be passed in the earthly build
provider-image:   
    FROM --platform=linux/${ARCH} +base-image
    # added PROVIDER_K8S_VERSION to fix missing image in ghcr.io/kairos-io/provider-*
    ARG K8S_VERSION=1.26.4
    ARG IMAGE_REPO
    IF [ "$CUSTOM_TAG" != "" ]
        ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPO:$K8S_DISTRIBUTION-$K8S_VERSION-$PE_VERSION-$CUSTOM_TAG
    ELSE
        ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPO:$K8S_DISTRIBUTION-$K8S_VERSION-$PE_VERSION
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

    COPY  --platform=linux/${ARCH} +kairos-provider-image/ /
    COPY +stylus-image/etc/kairos/branding /etc/kairos/branding
    COPY +stylus-image/oem/stylus_config.yaml /etc/kairos/branding/stylus_config.yaml
    COPY +stylus-image/etc/elemental/config.yaml /etc/elemental/config.yaml

    IF [ "$IS_UKI" = "true" ]
        COPY +internal-slink/slink /usr/bin/slink
        COPY +install-k8s/ /k8s
        RUN slink --source /k8s/ --target /opt/k8s
        RUN rm -f /usr/bin/slink
        RUN rm -rf /k8s
    ELSE
        COPY +install-k8s/ /
    END

    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

    COPY (+download-etcdctl/etcdctl) /usr/bin/

    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id

    SAVE IMAGE --push $IMAGE_PATH


provider-image-rootfs:
    FROM --platform=linux/${ARCH} +provider-image
    SAVE ARTIFACT --keep-own /. rootfs

build-provider-trustedboot-image:
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    COPY --platform=linux/${ARCH} --keep-own +provider-image-rootfs/rootfs /build/image
    COPY keys /keys
    RUN /entrypoint.sh build-uki dir:/build/image -t container -d /output -k /keys
    SAVE ARTIFACT /output/* AS LOCAL ./trusted-boot/

stylus-image:
    FROM $STYLUS_BASE
    SAVE ARTIFACT ./*
    SAVE ARTIFACT /etc/kairos/branding
    SAVE ARTIFACT /etc/elemental/config.yaml
    SAVE ARTIFACT /oem/stylus_config.yaml

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
    FROM DOCKERFILE --build-arg BASE=$BASE_IMAGE --build-arg PROXY_CERT_PATH=$PROXY_CERT_PATH \ 
    --build-arg OS_DISTRIBUTION=$OS_DISTRIBUTION --build-arg HTTP_PROXY=$HTTP_PROXY --build-arg HTTPS_PROXY=$HTTPS_PROXY \
    --build-arg NO_PROXY=$NO_PROXY .

    IF [ "$IS_JETSON" = "true" ]
        COPY mount.yaml /system/oem/mount.yaml
    END

    IF [ "$IS_UKI" = "true" ]
        COPY stylus_uki.yaml /system/oem/stylus_uki.yaml
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
        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /etc/ssl/certs
            RUN  update-ca-certificates
        END

        RUN apt update && \
            apt install --no-install-recommends kbd zstd vim iputils-ping bridge-utils curl tcpdump ethtool -y
        IF [ "$IS_UKI" = "false" ]
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

            RUN if [ ! -f /usr/bin/grub2-editenv ]; then \
                ln -s /usr/sbin/grub-editenv /usr/bin/grub2-editenv; \
            fi

            RUN rm -rf /var/cache/* && \
                apt clean
        END 
            
    # IF OS Type is Opensuse
    ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$ARCH" = "amd64" ]
        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /usr/share/pki/trust/anchors
            RUN  update-ca-certificates
        END

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
        RUN zypper install -y zstd vim iputils bridge-utils curl ethtool tcpdump
        RUN zypper cc && \
            zypper clean
    END

    IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
        RUN zypper install -y apparmor-parser apparmor-profiles
        RUN zypper cc && \
            zypper clean
        RUN cp /sbin/apparmor_parser /usr/bin/apparmor_parser
    END

     IF [ "$OS_DISTRIBUTION" = "rhel" ]
        RUN yum install -y openssl
    END

    IF [ "$OS_DISTRIBUTION" = "sles" ]
         RUN cp /sbin/apparmor_parser /usr/bin/apparmor_parser
    END

    IF [ "$ARCH" = "arm64" ]
        RUN mkdir -p /etc/luet/repos.conf.d && luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo-arm --priority 1 -y && luet repo update
    ELSE IF [ "$ARCH" = "amd64" ]
        RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add spectro --type docker --url gcr.io/spectro-dev-public/luet-repo  --priority 1 -y && \
        luet repo update
    END

    DO +OS_RELEASE --OS_VERSION=$KAIROS_VERSION

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
    IF [ "$IS_UKI" = "false" ]
        COPY --platform=linux/${ARCH} +stylus-image/ /
    ELSE
        COPY +luet/luet /usr/bin/luet
        COPY --platform=linux/${ARCH} +stylus-image/system /system
    END
    COPY overlay/files/ /
    
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id
    IF [ "$CUSTOM_TAG" != "" ]
        SAVE IMAGE palette-installer-image:$PE_VERSION-$CUSTOM_TAG
    ELSE
        SAVE IMAGE palette-installer-image:$PE_VERSION
    END

uki:
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    COPY (+provider-image/) /provider-image
    DO +OS_RELEASE --OS_VERSION=$KAIROS_VERSION
    COPY keys /keys
    RUN ls -liah /keys
    RUN /entrypoint.sh build-uki dir:/provider-image -t container -d /iso -k /keys
    WORKDIR /iso
    SAVE ARTIFACT /iso/*
    SAVE IMAGE --push $IMAGE_PATH 

OS_RELEASE:
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
    ARG ARTIFACT=kairos-core-${OS_DISTRIBUTION}-$OS_VERSION
    ARG KAIROS_RELEASE=${OS_VERSION}

    # update OS-release file
    # RUN sed -i -n '/KAIROS_/!p' /etc/os-release
    RUN envsubst >>/etc/os-release </usr/lib/os-release.tmpl
