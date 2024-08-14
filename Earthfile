VERSION 0.6
ARG TARGETOS
ARG TARGETARCH

# Default image repositories used in the builds.
ARG ALPINE_IMG=gcr.io/spectro-images-public/alpine:3.20.2
ARG SPECTRO_PUB_REPO=gcr.io/spectro-images-public
ARG SPECTRO_LUET_REPO=gcr.io/spectro-dev-public
ARG KAIROS_BASE_IMAGE_URL=gcr.io/spectro-images-public
ARG ETCD_REPO=https://github.com/etcd-io
ARG LUET_PROJECT=luet-repo
FROM $SPECTRO_PUB_REPO/canvos/alpine-cert:v1.0.0

# Spectro Cloud and Kairos tags.
ARG PE_VERSION=v4.4.7
ARG SPECTRO_LUET_VERSION=v1.3.4-alpha1
ARG KAIROS_VERSION=v3.0.14
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.201.0
ARG OSBUILDER_IMAGE=quay.io/kairos/osbuilder-tools:$OSBUILDER_VERSION
ARG K3S_PROVIDER_VERSION=v4.4.2
ARG KUBEADM_PROVIDER_VERSION=v4.4.1
ARG RKE2_PROVIDER_VERSION=v4.4.1

# Variables used in the builds. Update for ADVANCED use cases only. Modify in .arg file or via CLI arguments.
ARG OS_DISTRIBUTION
ARG OS_VERSION
ARG K8S_VERSION
ARG IMAGE_REGISTRY
ARG IMAGE_REPO=$OS_DISTRIBUTION
ARG ISO_NAME=installer
ARG K8S_DISTRIBUTION
ARG CUSTOM_TAG
ARG CLUSTERCONFIG
ARG EDGE_CUSTOM_CONFIG=.edge-custom-config.yaml
ARG ARCH
ARG DISABLE_SELINUX=true
ARG CIS_HARDENING=false
ARG UBUNTU_PRO_KEY

ARG FIPS_ENABLED=false
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy=${HTTP_PROXY}
ARG https_proxy=${HTTPS_PROXY}
ARG no_proxy=${NO_PROXY}
ARG PROXY_CERT_PATH

ARG UPDATE_KERNEL=false
ARG ETCD_VERSION="v3.5.13"

# Two node variables
ARG TWO_NODE=false
ARG KINE_VERSION=0.11.4

# UKI Variables
ARG IS_UKI=false
ARG INCLUDE_MS_SECUREBOOT_KEYS=true
ARG AUTO_ENROLL_SECUREBOOT_KEYS=false
ARG UKI_BRING_YOUR_OWN_KEYS=false

ARG CMDLINE="stylus.registration"
ARG BRANDING="Palette eXtended Kubernetes Edge"

# EFI size check
ARG EFI_MAX_SIZE=2048
ARG EFI_IMG_SIZE=2200

# internal variables
ARG GOLANG_VERSION=1.22
ARG DEBUG=false
ARG BUILDER_3RDPARTY_VERSION=4.4

IF [ "$OS_DISTRIBUTION" = "ubuntu" ] && [ "$BASE_IMAGE" = "" ]
    IF [ "$OS_VERSION" == 22 ] || [ "$OS_VERSION" == 20 ]
        ARG BASE_IMAGE_TAG=kairos-$OS_DISTRIBUTION:$OS_VERSION.04-core-$ARCH-generic-$KAIROS_VERSION
    ELSE
        IF [ "$IS_UKI" = "true" ]
            ARG BASE_IMAGE_TAG=kairos-$OS_DISTRIBUTION:$OS_VERSION-core-$ARCH-generic-$KAIROS_VERSION-uki
        ELSE
            ARG BASE_IMAGE_TAG=kairos-$OS_DISTRIBUTION:$OS_VERSION-core-$ARCH-generic-$KAIROS_VERSION
        END
    END
    ARG BASE_IMAGE=$KAIROS_BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$BASE_IMAGE" = "" ]
    ARG BASE_IMAGE_TAG=kairos-opensuse:leap-$OS_VERSION-core-$ARCH-generic-$KAIROS_VERSION
    ARG BASE_IMAGE=$KAIROS_BASE_IMAGE_URL/$BASE_IMAGE_TAG
ELSE IF [ "$OS_DISTRIBUTION" = "rhel" ] || [ "$OS_DISTRIBUTION" = "sles" ]
    # Check for default value for rhel
    ARG BASE_IMAGE
END

IF [[ "$BASE_IMAGE" =~ "nvidia-jetson-agx-orin" ]]
    ARG IS_JETSON=true
END

IF [ "$FIPS_ENABLED" = "true" ]
    ARG BIN_TYPE=vertex
    ARG STYLUS_BASE=$SPECTRO_PUB_REPO/stylus-framework-fips-linux-$ARCH:$PE_VERSION
    ARG STYLUS_PACKAGE_BASE=$SPECTRO_PUB_REPO/stylus-fips-linux-$ARCH:$PE_VERSION
    ARG CLI_IMAGE=$SPECTRO_PUB_REPO/palette-edge-cli-fips-${TARGETARCH}:${PE_VERSION}
ELSE
    ARG BIN_TYPE=palette
    ARG STYLUS_BASE=$SPECTRO_PUB_REPO/stylus-framework-linux-$ARCH:$PE_VERSION
    ARG STYLUS_PACKAGE_BASE=$SPECTRO_PUB_REPO/stylus-linux-$ARCH:$PE_VERSION
    ARG CLI_IMAGE=$SPECTRO_PUB_REPO/palette-edge-cli-${TARGETARCH}:${PE_VERSION}
END

IF [ "$CUSTOM_TAG" != "" ]
    ARG IMAGE_TAG=$PE_VERSION-$CUSTOM_TAG
ELSE
    ARG IMAGE_TAG=$PE_VERSION
END

ARG IMAGE_PATH=$IMAGE_REGISTRY/$IMAGE_REPO:$K8S_DISTRIBUTION-$K8S_VERSION-$IMAGE_TAG
ARG ISO_DISK_IMG=$IMAGE_REGISTRY/$IMAGE_REPO:$IMAGE_TAG-iso
ARG CMDLINE="stylus.registration"

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
    IF [ "$IS_UKI" = "true" ]
        ARG TARGET=uki-provider-image
    ELSE
        ARG TARGET=provider-image
    END
    IF [ "$K8S_VERSION" = "" ]
        IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
           BUILD  +$TARGET --K8S_VERSION=1.24.6
           BUILD  +$TARGET --K8S_VERSION=1.25.2
           BUILD  +$TARGET --K8S_VERSION=1.25.13
           BUILD  +$TARGET --K8S_VERSION=1.25.15
           BUILD  +$TARGET --K8S_VERSION=1.26.4
           BUILD  +$TARGET --K8S_VERSION=1.26.8
           BUILD  +$TARGET --K8S_VERSION=1.26.10
           BUILD  +$TARGET --K8S_VERSION=1.26.12
           BUILD  +$TARGET --K8S_VERSION=1.26.15
           BUILD  +$TARGET --K8S_VERSION=1.27.2
           BUILD  +$TARGET --K8S_VERSION=1.27.5
           BUILD  +$TARGET --K8S_VERSION=1.27.7
           BUILD  +$TARGET --K8S_VERSION=1.27.9
           BUILD  +$TARGET --K8S_VERSION=1.27.11
           BUILD  +$TARGET --K8S_VERSION=1.27.15
           BUILD  +$TARGET --K8S_VERSION=1.27.16
           BUILD  +$TARGET --K8S_VERSION=1.28.2
           BUILD  +$TARGET --K8S_VERSION=1.28.5
           BUILD  +$TARGET --K8S_VERSION=1.28.9
           BUILD  +$TARGET --K8S_VERSION=1.28.11
           BUILD  +$TARGET --K8S_VERSION=1.28.12
           BUILD  +$TARGET --K8S_VERSION=1.29.0
           BUILD  +$TARGET --K8S_VERSION=1.29.6
           BUILD  +$TARGET --K8S_VERSION=1.29.7
       ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
           BUILD  +$TARGET --K8S_VERSION=1.24.6
           BUILD  +$TARGET --K8S_VERSION=1.25.2
           BUILD  +$TARGET --K8S_VERSION=1.25.13
           BUILD  +$TARGET --K8S_VERSION=1.25.15
           BUILD  +$TARGET --K8S_VERSION=1.26.4
           BUILD  +$TARGET --K8S_VERSION=1.26.8
           BUILD  +$TARGET --K8S_VERSION=1.26.10
           BUILD  +$TARGET --K8S_VERSION=1.26.12
           BUILD  +$TARGET --K8S_VERSION=1.26.14
           BUILD  +$TARGET --K8S_VERSION=1.26.15
           BUILD  +$TARGET --K8S_VERSION=1.27.2
           BUILD  +$TARGET --K8S_VERSION=1.27.5
           BUILD  +$TARGET --K8S_VERSION=1.27.7
           BUILD  +$TARGET --K8S_VERSION=1.27.9
           BUILD  +$TARGET --K8S_VERSION=1.27.11
           BUILD  +$TARGET --K8S_VERSION=1.27.13
           BUILD  +$TARGET --K8S_VERSION=1.27.14
           BUILD  +$TARGET --K8S_VERSION=1.27.15
           BUILD  +$TARGET --K8S_VERSION=1.28.2
           BUILD  +$TARGET --K8S_VERSION=1.28.5
           BUILD  +$TARGET --K8S_VERSION=1.28.7
           BUILD  +$TARGET --K8S_VERSION=1.28.9
           BUILD  +$TARGET --K8S_VERSION=1.28.10
           BUILD  +$TARGET --K8S_VERSION=1.28.11
           BUILD  +$TARGET --K8S_VERSION=1.29.3
           BUILD  +$TARGET --K8S_VERSION=1.29.4
           BUILD  +$TARGET --K8S_VERSION=1.29.5
           BUILD  +$TARGET --K8S_VERSION=1.29.6
       ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
           BUILD  +$TARGET --K8S_VERSION=1.24.6
           BUILD  +$TARGET --K8S_VERSION=1.25.2
           BUILD  +$TARGET --K8S_VERSION=1.25.13
           BUILD  +$TARGET --K8S_VERSION=1.25.15
           BUILD  +$TARGET --K8S_VERSION=1.26.4
           BUILD  +$TARGET --K8S_VERSION=1.26.8
           BUILD  +$TARGET --K8S_VERSION=1.26.10
           BUILD  +$TARGET --K8S_VERSION=1.26.14
           BUILD  +$TARGET --K8S_VERSION=1.27.2
           BUILD  +$TARGET --K8S_VERSION=1.27.5
           BUILD  +$TARGET --K8S_VERSION=1.27.7
           BUILD  +$TARGET --K8S_VERSION=1.27.11
           BUILD  +$TARGET --K8S_VERSION=1.27.15
           BUILD  +$TARGET --K8S_VERSION=1.28.2
           BUILD  +$TARGET --K8S_VERSION=1.28.7
           BUILD  +$TARGET --K8S_VERSION=1.28.11
           BUILD  +$TARGET --K8S_VERSION=1.29.2
           BUILD  +$TARGET --K8S_VERSION=1.29.6
       END
    ELSE
        BUILD  +$TARGET --K8S_VERSION="$K8S_VERSION"
    END

build-provider-images-fips:
    IF [ "$K8S_VERSION" = "" ]
        IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
           BUILD  +provider-image --K8S_VERSION=1.24.13
           BUILD  +provider-image --K8S_VERSION=1.25.9
           BUILD  +provider-image --K8S_VERSION=1.26.4
           BUILD  +provider-image --K8S_VERSION=1.26.12
           BUILD  +provider-image --K8S_VERSION=1.26.15
           BUILD  +provider-image --K8S_VERSION=1.27.2
           BUILD  +provider-image --K8S_VERSION=1.27.9
           BUILD  +provider-image --K8S_VERSION=1.27.14
           BUILD  +provider-image --K8S_VERSION=1.27.15
           BUILD  +provider-image --K8S_VERSION=1.27.16
           BUILD  +provider-image --K8S_VERSION=1.28.5
           BUILD  +provider-image --K8S_VERSION=1.28.10
           BUILD  +provider-image --K8S_VERSION=1.28.11
           BUILD  +provider-image --K8S_VERSION=1.28.12
           BUILD  +provider-image --K8S_VERSION=1.29.0
           BUILD  +provider-image --K8S_VERSION=1.29.5
           BUILD  +provider-image --K8S_VERSION=1.29.6
           BUILD  +provider-image --K8S_VERSION=1.29.7
        ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
           BUILD  +provider-image --K8S_VERSION=1.24.6
           BUILD  +provider-image --K8S_VERSION=1.25.0
           BUILD  +provider-image --K8S_VERSION=1.25.2
           BUILD  +provider-image --K8S_VERSION=1.26.4
           BUILD  +provider-image --K8S_VERSION=1.26.12
           BUILD  +provider-image --K8S_VERSION=1.26.14
           BUILD  +provider-image --K8S_VERSION=1.27.2
           BUILD  +provider-image --K8S_VERSION=1.27.9
           BUILD  +provider-image --K8S_VERSION=1.27.11
           BUILD  +provider-image --K8S_VERSION=1.27.14
           BUILD  +provider-image --K8S_VERSION=1.27.15
           BUILD  +provider-image --K8S_VERSION=1.28.5
           BUILD  +provider-image --K8S_VERSION=1.28.7
           BUILD  +provider-image --K8S_VERSION=1.28.10
           BUILD  +provider-image --K8S_VERSION=1.28.11
           BUILD  +provider-image --K8S_VERSION=1.29.0
           BUILD  +provider-image --K8S_VERSION=1.29.3
           BUILD  +provider-image --K8S_VERSION=1.29.5
           BUILD  +provider-image --K8S_VERSION=1.29.6
        ELSE
           BUILD  +provider-image --K8S_VERSION=1.24.6
           BUILD  +provider-image --K8S_VERSION=1.25.2
           BUILD  +provider-image --K8S_VERSION=1.26.4
           BUILD  +provider-image --K8S_VERSION=1.26.12
           BUILD  +provider-image --K8S_VERSION=1.26.14
           BUILD  +provider-image --K8S_VERSION=1.27.2
           BUILD  +provider-image --K8S_VERSION=1.27.9
           BUILD  +provider-image --K8S_VERSION=1.27.11
           BUILD  +provider-image --K8S_VERSION=1.27.15
           BUILD  +provider-image --K8S_VERSION=1.28.5
           BUILD  +provider-image --K8S_VERSION=1.28.7
           BUILD  +provider-image --K8S_VERSION=1.28.11
           BUILD  +provider-image --K8S_VERSION=1.29.0
           BUILD  +provider-image --K8S_VERSION=1.29.2
           BUILD  +provider-image --K8S_VERSION=1.29.6
        END
    ELSE
        BUILD  +provider-image --K8S_VERSION="$K8S_VERSION"
    END

BASE_ALPINE:
    COMMAND
    IF [ ! -z $PROXY_CERT_PATH ]
        COPY sc.crt /etc/ssl/certs
        RUN update-ca-certificates
    END
    RUN apk add curl

iso-image-rootfs:
    FROM --platform=linux/${ARCH} +iso-image
    SAVE ARTIFACT --keep-own /. rootfs

uki-iso:
    WORKDIR /build
    COPY --platform=linux/${ARCH} +build-uki-iso/ .
    SAVE ARTIFACT /build/* AS LOCAL ./build/

uki-provider-image:
    FROM --platform=linux/${ARCH} +ubuntu-systemd
    RUN apt-get update && apt-get install -y rsync

    WORKDIR /
    COPY --if-exists overlay/files/etc/ /etc/
    IF [ -f /etc/logrotate.d/stylus.conf ]
        RUN chmod 644 /etc/logrotate.d/stylus.conf
    END
    COPY (+third-party/luet --binary=luet) /usr/bin/luet
    COPY +kairos-agent/kairos-agent /usr/bin/kairos-agent
    COPY --platform=linux/${ARCH} +trust-boot-unpack/ /trusted-boot
    COPY --platform=linux/${ARCH} +install-k8s/ /k8s
    COPY --if-exists "$EDGE_CUSTOM_CONFIG" /oem/.edge_custom_config.yaml
    SAVE IMAGE --push $IMAGE_PATH

trust-boot-unpack:
    COPY (+third-party/luet --binary=luet) /usr/bin/luet
    COPY --platform=linux/${ARCH} +build-provider-trustedboot-image/ /image
    RUN FILE="file:/$(find /image -type f -name "*.tar" | head -n 1)" && \
        luet util unpack $FILE /trusted-boot
    SAVE ARTIFACT /trusted-boot/*

stylus-image-pack:  
    COPY (+third-party/luet --binary=luet) /usr/bin/luet
    COPY --platform=linux/${ARCH} +stylus-package-image/ /stylus
    RUN cd stylus && tar -czf ../stylus.tar *
    RUN luet util pack $STYLUS_BASE stylus.tar stylus-image.tar
    SAVE ARTIFACT stylus-image.tar AS LOCAL ./build/

kairos-agent:
    FROM --platform=linux/${ARCH} $BASE_IMAGE
    SAVE ARTIFACT /usr/bin/kairos-agent /kairos-agent

install-k8s:
    FROM --platform=linux/${ARCH} $ALPINE_IMG
    COPY (+third-party/luet --binary=luet) /usr/bin/luet

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

    IF [ "$ARCH" = "arm64" ]
        ARG LUET_REPO=$LUET_PROJECT-arm
    ELSE IF [ "$ARCH" = "amd64" ]
        ARG LUET_REPO=$LUET_PROJECT
    END
    RUN mkdir -p /etc/luet/repos.conf.d && \
        luet repo add spectro --type docker --url $SPECTRO_LUET_REPO/$LUET_REPO/$SPECTRO_LUET_VERSION  --priority 1 -y && \
        luet repo update

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        RUN luet install -y container-runtime/containerd --system-target /output
    END

    IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
       RUN luet install -y container-runtime/containerd-fips --system-target /output
    END
    RUN luet install -y k8s/$K8S_DISTRIBUTION@$BASE_K8S_VERSION --system-target /output && luet cleanup
    RUN rm -rf /output/var/cache/*
    SAVE ARTIFACT /output/*

build-uki-iso:
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    ENV ISO_NAME=${ISO_NAME}
    COPY overlay/files-iso/ /overlay/
    COPY --if-exists +validate-user-data/user-data /overlay/config.yaml
    COPY --platform=linux/${ARCH} +stylus-image-pack/stylus-image.tar /overlay/stylus-image.tar
    COPY --platform=linux/${ARCH} (+third-party/luet --binary=luet)  /overlay/luet
 
    COPY --if-exists content-*/*.zst /overlay/opt/spectrocloud/content/
    COPY --if-exists "$EDGE_CUSTOM_CONFIG" /overlay/.edge_custom_config.yaml
    RUN if [ -n "$(ls /overlay/opt/spectrocloud/content/*.zst 2>/dev/null)" ]; then \
        for file in /overlay/opt/spectrocloud/content/*.zst; do \
            split --bytes=3GB --numeric-suffixes "$file" /overlay/opt/spectrocloud/content/$(basename "$file")_part; \
        done; \
        rm -f /overlay/opt/spectrocloud/content/*.zst; \
    fi
    
    #check if clusterconfig is passed in
    IF [ "$CLUSTERCONFIG" != "" ]
        COPY --if-exists "$CLUSTERCONFIG" /overlay/opt/spectrocloud/clusterconfig/spc.tgz
    END

    COPY --if-exists local-ui.tar /overlay/opt/spectrocloud/
    RUN if [ -f /overlay/opt/spectrocloud/local-ui.tar ]; then \
        tar -xf /overlay/opt/spectrocloud/local-ui.tar -C /overlay/opt/spectrocloud && \
        rm -f /overlay/opt/spectrocloud/local-ui.tar; \
    fi

    WORKDIR /build
    COPY --platform=linux/${ARCH} --keep-own +iso-image-rootfs/rootfs /build/image
    IF [ "$ARCH" = "arm64" ]
       RUN CMD="/entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay dir:/build/image --output /iso/ --arch $ARCH" && \
           if [ "$DEBUG" = "true" ]; then CMD="$CMD --debug"; else CMD="$CMD"; fi && \
              $CMD
    ELSE IF [ "$ARCH" = "amd64" ]
       COPY secure-boot/enrollment/ secure-boot/private-keys/ secure-boot/public-keys/ /keys
       RUN ls -liah /keys
       RUN mkdir /iso
       IF [ "$AUTO_ENROLL_SECUREBOOT_KEYS" = "true" ]
           RUN enki --config-dir /config build-uki dir:/build/image --extend-cmdline "$CMDLINE" --overlay-iso /overlay --secure-boot-enroll force -t iso -d /iso -k /keys --boot-branding "$BRANDING"
       ELSE
           RUN enki --config-dir /config build-uki dir:/build/image --extend-cmdline "$CMDLINE" --overlay-iso /overlay -t iso -d /iso -k /keys --boot-branding "$BRANDING"
       END
    END
    WORKDIR /iso
    RUN mv /iso/*.iso $ISO_NAME.iso
    SAVE ARTIFACT /iso/*

iso:
    WORKDIR /build
    IF [ "$IS_UKI" = "true" ]
        COPY --platform=linux/${ARCH} +build-uki-iso/ .
    ELSE
        COPY --platform=linux/${ARCH} +build-iso/ .
    END
    SAVE ARTIFACT /build/* AS LOCAL ./build/

validate-user-data:
    FROM --platform=linux/${TARGETARCH} $CLI_IMAGE
    COPY --if-exists user-data /user-data

    RUN chmod +x /usr/local/bin/palette-edge-cli;
    RUN if [ -f /user-data ]; then \
            /usr/local/bin/palette-edge-cli validate -f /user-data; \
        else \
            echo "user-data file does not exist."; \
        fi
    SAVE ARTIFACT --if-exists /user-data


build-iso:
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    ENV ISO_NAME=${ISO_NAME}
    COPY overlay/files-iso/ /overlay/
    COPY --if-exists +validate-user-data/user-data /overlay/files-iso/config.yaml
    COPY --if-exists content-*/*.zst /overlay/opt/spectrocloud/content/
    COPY --if-exists "$EDGE_CUSTOM_CONFIG" /overlay/.edge_custom_config.yaml
    RUN if [ -n "$(ls /overlay/opt/spectrocloud/content/*.zst 2>/dev/null)" ]; then \
        for file in /overlay/opt/spectrocloud/content/*.zst; do \
            split --bytes=3GB --numeric-suffixes "$file" /overlay/opt/spectrocloud/content/$(basename "$file")_part; \
        done; \
        rm -f /overlay/opt/spectrocloud/content/*.zst; \
    fi
    #check if clusterconfig is passed in
    IF [ "$CLUSTERCONFIG" != "" ]
        COPY --if-exists "$CLUSTERCONFIG" /overlay/opt/spectrocloud/clusterconfig/spc.tgz
    END

    WORKDIR /build
    COPY --platform=linux/${ARCH} --keep-own +iso-image-rootfs/rootfs /build/image

    COPY --if-exists local-ui.tar /build/image/opt/spectrocloud/
    RUN if [ -f /build/image/opt/spectrocloud/local-ui.tar ]; then \
        tar -xf /build/image/opt/spectrocloud/local-ui.tar -C /build/image/opt/spectrocloud && \
        rm -f /build/image/opt/spectrocloud/local-ui.tar; \
    fi
    
    IF [ "$ARCH" = "arm64" ]
        RUN CMD="/entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay dir:/build/image --output /iso/ --arch $ARCH" && \
            if [ "$DEBUG" = "true" ]; then CMD="$CMD --debug"; else CMD="$CMD"; fi && \
                $CMD 
    ELSE IF [ "$ARCH" = "amd64" ]
        RUN CMD="/entrypoint.sh --name $ISO_NAME build-iso --date=false --overlay-iso /overlay dir:/build/image --output /iso/ --arch x86_64" && \
            if [ "$DEBUG" = "true" ]; then CMD="$CMD --debug"; else CMD="$CMD"; fi && \
                $CMD
    END
    WORKDIR /iso
    RUN sha256sum $ISO_NAME.iso > $ISO_NAME.iso.sha256
    SAVE ARTIFACT /iso/*

### UKI targets
## Generate UKI keys
#  Default Expiry 15 years
## earthly +uki-genkey --MY_ORG="ACME Corp" --EXPIRATION_IN_DAYS=5475
uki-genkey:
    ARG MY_ORG="ACME Corp"
    ARG EXPIRATION_IN_DAYS=5475
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE

    IF [ "$UKI_BRING_YOUR_OWN_KEYS" = "false" ]
        RUN --no-cache mkdir -p /custom-keys
        COPY --if-exists secure-boot/exported-keys/ /custom-keys
        IF [ "$INCLUDE_MS_SECUREBOOT_KEYS" = "false" ]
            RUN --no-cache if [[ -f /custom-keys/KEK && -f /custom-keys/db ]]; then \
                  echo "Generating Secure Boot keys, including exported UEFI keys..." && \
                  /entrypoint.sh genkey "$MY_ORG" --custom-cert-dir /custom-keys --skip-microsoft-certs-I-KNOW-WHAT-IM-DOING --expiration-in-days $EXPIRATION_IN_DAYS -o /keys; else \
                  echo "Generating Secure Boot keys..." && \
                  /entrypoint.sh genkey "$MY_ORG" --skip-microsoft-certs-I-KNOW-WHAT-IM-DOING --expiration-in-days $EXPIRATION_IN_DAYS -o /keys; fi
        ELSE
            RUN --no-cache if [[ -f /custom-keys/KEK && -f /custom-keys/db ]]; then \
                  echo "Generating Secure Boot keys, including exported UEFI keys and Microsoft keys..." && \
                  /entrypoint.sh genkey "$MY_ORG" --custom-cert-dir /custom-keys --expiration-in-days $EXPIRATION_IN_DAYS -o /keys; else \
                  echo "Generating Secure Boot keys, including Microsoft keys..." && \
                  /entrypoint.sh genkey "$MY_ORG" --expiration-in-days $EXPIRATION_IN_DAYS -o /keys; fi
        END
        RUN --no-cache mkdir -p /private-keys
        RUN --no-cache mkdir -p /public-keys
        RUN --no-cache cd /keys; mv *.key tpm2-pcr-private.pem /private-keys
        RUN --no-cache cd /keys; mv *.pem /public-keys
    ELSE
        COPY +uki-byok/ /keys
    END

    SAVE ARTIFACT --if-exists /keys AS LOCAL ./secure-boot/enrollment
    IF [ "$UKI_BRING_YOUR_OWN_KEYS" = "false" ]
        SAVE ARTIFACT --if-exists /private-keys AS LOCAL ./secure-boot/private-keys
        SAVE ARTIFACT --if-exists /public-keys AS LOCAL ./secure-boot/public-keys
    END

download-sbctl:
    DO +BASE_ALPINE
    RUN curl -Ls https://github.com/Foxboron/sbctl/releases/download/0.13/sbctl-0.13-linux-amd64.tar.gz | tar -xvzf - && mv sbctl/sbctl /usr/bin/sbctl
    SAVE ARTIFACT /usr/bin/sbctl

uki-byok:
    FROM +ubuntu-systemd

    RUN apt-get update && apt-get install -y efitools curl
    COPY +download-sbctl/sbctl /usr/bin/sbctl
    COPY --if-exists secure-boot/exported-keys/ /exported-keys
    COPY secure-boot/private-keys/ secure-boot/public-keys /keys
    WORKDIR /keys
    RUN sbctl import-keys \
        --pk-key /keys/PK.key \
        --pk-cert /keys/PK.pem \
        --kek-key /keys/KEK.key \
        --kek-cert /keys/KEK.pem \
        --db-key /keys/db.key \
        --db-cert /keys/db.pem
    RUN sbctl create-keys
    IF [ "$INCLUDE_MS_SECUREBOOT_KEYS" = "false" ]
        RUN sbctl enroll-keys --export esl --yes-this-might-brick-my-machine
    ELSE
        RUN sbctl enroll-keys --export esl --yes-this-might-brick-my-machine --microsoft
    END
    RUN mkdir -p /output
    RUN cp PK.esl  /output/PK.esl  2>/dev/null
    RUN cp KEK.esl /output/KEK.esl 2>/dev/null
    RUN cp db.esl  /output/db.esl  2>/dev/null
    RUN if [ -f dbx.esl ]; then cp dbx.esl /output/dbx.esl; else touch /output/dbx.esl; fi
    RUN [ -f /exported-keys/KEK ] && cat /exported-keys/KEK >> /output/KEK.esl || true
    RUN [ -f /exported-keys/db ]  && cat /exported-keys/db  >> /output/db.esl  || true
    RUN [ -f /exported-keys/dbx ] && cat /exported-keys/dbx >> /output/dbx.esl || true
    
    WORKDIR /output
    RUN sign-efi-sig-list -c /keys/PK.pem  -k /keys/PK.key  PK  PK.esl  PK.auth
    RUN sign-efi-sig-list -c /keys/PK.pem  -k /keys/PK.key  KEK KEK.esl KEK.auth
    RUN sign-efi-sig-list -c /keys/KEK.pem -k /keys/KEK.key db  db.esl  db.auth
    RUN sign-efi-sig-list -c /keys/KEK.pem -k /keys/KEK.key dbx dbx.esl dbx.auth

    RUN sig-list-to-certs 'PK.esl' 'PK'
    RUN sig-list-to-certs 'KEK.esl' 'KEK'
    RUN sig-list-to-certs 'db.esl' 'db'

    RUN cp PK-0.der  PK.der  2>/dev/null
    RUN cp KEK-0.der KEK.der 2>/dev/null
    RUN cp db-0.der  db.der  2>/dev/null

    SAVE ARTIFACT /output/*

secure-boot-dirs:
    FROM --platform=linux/${ARCH} ubuntu:latest
    RUN mkdir -p --mode=0644 /secure-boot/enrollment
    RUN mkdir -p --mode=0600 /secure-boot/exported-keys
    RUN mkdir -p --mode=0600 /secure-boot/private-keys
    RUN mkdir -p --mode=0644 /secure-boot/public-keys
    COPY --if-exists --keep-ts secure-boot/enrollment/ /secure-boot/enrollment
    COPY --if-exists --keep-ts secure-boot/exported-keys/ /secure-boot/exported-keys
    COPY --if-exists --keep-ts secure-boot/private-keys/ /secure-boot/private-keys
    COPY --if-exists --keep-ts secure-boot/public-keys/ /secure-boot/public-keys
    RUN chmod 0600 /secure-boot/exported-keys
    RUN chmod 0600 /secure-boot/private-keys
    RUN chmod 0644 /secure-boot/public-keys
    SAVE ARTIFACT --keep-ts /secure-boot AS LOCAL ./secure-boot

# Used to create the provider images. The --K8S_VERSION will be passed in the earthly build.
provider-image:
    FROM --platform=linux/${ARCH} +base-image
    # added PROVIDER_K8S_VERSION to fix missing image in ghcr.io/kairos-io/provider-*
    ARG IMAGE_REPO

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ] || [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
        IF [ "$OS_DISTRIBUTION" = "ubuntu" ] &&  [ "$ARCH" = "amd64" ] && [ "$K8S_DISTRIBUTION" = "kubeadm" ]
            RUN kernel=$(ls /lib/modules | tail -n1) && if ! ls /usr/src | grep linux-headers-$kernel; then apt-get update && apt-get install -y "linux-headers-${kernel}"; fi
        END
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    COPY --if-exists overlay/files/etc/ /etc/
    IF [ -f /etc/logrotate.d/stylus.conf ]
        RUN chmod 644 /etc/logrotate.d/stylus.conf
    END

    COPY  --platform=linux/${ARCH} +kairos-provider-image/ /
    COPY +stylus-image/etc/kairos/branding /etc/kairos/branding
    COPY +stylus-image/oem/stylus_config.yaml /etc/kairos/branding/stylus_config.yaml
    COPY +stylus-image/etc/elemental/config.yaml /etc/elemental/config.yaml
    COPY --if-exists "$EDGE_CUSTOM_CONFIG" /oem/.edge_custom_config.yaml

    IF [ "$IS_UKI" = "true" ]
        COPY +internal-slink/slink /usr/bin/slink
        COPY +install-k8s/ /k8s
        RUN slink --source /k8s/ --target /opt/k8s
        RUN rm -f /usr/bin/slink
        RUN rm -rf /k8s
        RUN ln -sf /opt/spectrocloud/bin/agent-provider-stylus /usr/local/bin/agent-provider-stylus
    ELSE
        COPY +install-k8s/ /
    END

    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli

    COPY (+third-party/etcdctl --binary=etcdctl) /usr/bin/

    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id

    IF $TWO_NODE
        # Install postgresql 16
        IF [ "$OS_DISTRIBUTION" = "ubuntu" ] &&  [ "$ARCH" = "amd64" ]
            RUN apt install -y ca-certificates curl && \
                install -d /usr/share/postgresql-common/pgdg && \
                curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
                echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
                apt update && \
                apt install -y postgresql-16 postgresql-contrib-16 iputils-ping
        ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$ARCH" = "amd64" ]
            RUN zypper --non-interactive --quiet addrepo --refresh -p 90 http://download.opensuse.org/repositories/server:database:postgresql/openSUSE_Tumbleweed/ PostgreSQL && \
                zypper --gpg-auto-import-keys ref && \
                zypper install -y postgresql-16 postgresql-server-16 postgresql-contrib iputils
        END

        # Install kine
        RUN mkdir -p /opt/spectrocloud/bin && \
            curl -L https://github.com/k3s-io/kine/releases/download/v${KINE_VERSION}/kine-amd64 | install -m 755 /dev/stdin /opt/spectrocloud/bin/kine

        # Ensure psql works ootb for the postgres user
        RUN su postgres -c 'echo "export PERL5LIB=/usr/share/perl/5.34:/usr/share/perl5:/usr/lib/x86_64-linux-gnu/perl/5.34" > ~/.bash_profile'
    END

    SAVE IMAGE --push $IMAGE_PATH

provider-image-rootfs:
    FROM --platform=linux/${ARCH} +provider-image
    SAVE ARTIFACT --keep-own /. rootfs

build-provider-trustedboot-image:
    FROM --platform=linux/${ARCH} $OSBUILDER_IMAGE
    COPY --platform=linux/${ARCH} --keep-own +provider-image-rootfs/rootfs /build/image
    COPY secure-boot/enrollment/ secure-boot/private-keys/ secure-boot/public-keys/ /keys
    RUN /entrypoint.sh build-uki dir:/build/image -t container -d /output -k /keys --boot-branding "Palette eXtended Kubernetes Edge"
    SAVE ARTIFACT /output/* AS LOCAL ./trusted-boot/

stylus-image:
    FROM --platform=linux/${ARCH} $STYLUS_BASE
    SAVE ARTIFACT --keep-own  ./*
    # SAVE ARTIFACT /etc/kairos/branding
    # SAVE ARTIFACT /etc/elemental/config.yaml
    # SAVE ARTIFACT /oem/stylus_config.yaml

stylus-package-image:
    FROM --platform=linux/${ARCH} $STYLUS_PACKAGE_BASE
    SAVE ARTIFACT --keep-own  ./*

kairos-provider-image:
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG PROVIDER_BASE=$SPECTRO_PUB_REPO/kairos-io/provider-kubeadm:$KUBEADM_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG PROVIDER_BASE=$SPECTRO_PUB_REPO/kairos-io/provider-kubeadm-fips:$KUBEADM_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG PROVIDER_BASE=$SPECTRO_PUB_REPO/kairos-io/provider-k3s:$K3S_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ] && $FIPS_ENABLED
        ARG PROVIDER_BASE=$SPECTRO_PUB_REPO/kairos-io/provider-rke2-fips:$RKE2_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
         ARG PROVIDER_BASE=$SPECTRO_PUB_REPO/kairos-io/provider-rke2:$RKE2_PROVIDER_VERSION
    END
    FROM --platform=linux/${ARCH} $PROVIDER_BASE
    SAVE ARTIFACT ./*

# base build image used to create the base image for all other image types
base-image:
    FROM DOCKERFILE --build-arg BASE=$BASE_IMAGE --build-arg PROXY_CERT_PATH=$PROXY_CERT_PATH \ 
    --build-arg OS_DISTRIBUTION=$OS_DISTRIBUTION --build-arg OS_VERSION=$OS_VERSION \ 
    --build-arg HTTP_PROXY=$HTTP_PROXY --build-arg HTTPS_PROXY=$HTTPS_PROXY \
    --build-arg NO_PROXY=$NO_PROXY .

    IF [ "$IS_JETSON" = "true" ]
        COPY cloudconfigs/mount.yaml /system/oem/mount.yaml
    END

    IF [ "$IS_UKI" = "true" ]
        COPY cloudconfigs/80_stylus_uki.yaml /system/oem/80_stylus_uki.yaml
    END

    IF [ "$ARCH" = "arm64" ]
        ARG LUET_REPO=$LUET_PROJECT-arm
    ELSE IF [ "$ARCH" = "amd64" ]
        ARG LUET_REPO=$LUET_PROJECT
    END

    RUN mkdir -p /etc/luet/repos.conf.d && \
      SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION luet repo add spectro --type docker --url $SPECTRO_LUET_REPO/$LUET_REPO/$SPECTRO_LUET_VERSION  --priority 1 -y && \
      luet repo update

    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ] || [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG BASE_K8S_VERSION=$K8S_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "k3s" ]
        ARG K8S_DISTRIBUTION_TAG=$K3S_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
        ARG K8S_DISTRIBUTION_TAG=$RKE2_FLAVOR_TAG
        ARG BASE_K8S_VERSION=$K8S_VERSION-$K8S_DISTRIBUTION_TAG
    END

    # OS == Ubuntu
    IF [ "$OS_DISTRIBUTION" = "ubuntu" ] &&  [ "$ARCH" = "amd64" ]
        IF [ ! -z "$UBUNTU_PRO_KEY" ]
            RUN sed -i '/^[[:space:]]*$/d' /etc/os-release && \
            apt update && apt-get install -y snapd && \
            pro attach $UBUNTU_PRO_KEY
        END

        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /etc/ssl/certs
            RUN  update-ca-certificates
        END

        RUN apt-get update && \
            apt-get install --no-install-recommends kbd zstd vim iputils-ping bridge-utils curl tcpdump ethtool rsyslog logrotate -y

        IF [ "$UPDATE_KERNEL" = "false" ]
            RUN if dpkg -l "linux-image-generic-hwe-$OS_VERSION" > /dev/null; then apt-mark hold "linux-image-generic-hwe-$OS_VERSION" "linux-headers-generic-hwe-$OS_VERSION" "linux-generic-hwe-$OS_VERSION" ; fi && \
                if dpkg -l linux-image-generic > /dev/null; then apt-mark hold linux-image-generic linux-headers-generic linux-generic; fi
        END

        IF [ "$IS_UKI" = "false" ]
            RUN apt-get update && \
                apt-get upgrade -y
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
                apt-get clean
        END

        IF [ "$CIS_HARDENING" = "true" ]
            COPY cis-harden/harden.sh /tmp/harden.sh
            RUN /tmp/harden.sh && rm /tmp/harden.sh
        END

        IF [ ! -z "$UBUNTU_PRO_KEY" ]
            RUN pro detach --assume-yes
        END

    # OS == Opensuse
    ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$ARCH" = "amd64" ]
        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /usr/share/pki/trust/anchors
            RUN update-ca-certificates
        END
        # Enable or Disable Kernel Updates
        IF [ "$UPDATE_KERNEL" = "false" ]
            RUN zypper al kernel-de*
        END

        RUN zypper refresh && zypper update -y

        IF [ -e "/usr/bin/dracut" ]
            RUN --no-cache kernel=$(ls /lib/modules | tail -n1) && depmod -a "${kernel}"
            RUN --no-cache kernel=$(ls /lib/modules | tail -n1) && dracut -f "/boot/initrd-${kernel}" "${kernel}" && ln -sf "initrd-${kernel}" /boot/initrd
        END

        RUN zypper install -y zstd vim iputils bridge-utils curl ethtool tcpdump && \
            zypper cc && \
            zypper clean
    END

    IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
        RUN zypper install -y apparmor-parser apparmor-profiles rsyslog logrotate
        RUN zypper cc && \
            zypper clean
        RUN if [ ! -e /usr/bin/apparmor_parser ]; then cp /sbin/apparmor_parser /usr/bin/apparmor_parser; fi
    END

    IF [ "$ARCH" = "arm64" ]
        ARG LUET_REPO=$LUET_PROJECT-arm
    ELSE IF [ "$ARCH" = "amd64" ]
        ARG LUET_REPO=$LUET_PROJECT
    END
    RUN --no-cache mkdir -p /etc/luet/repos.conf.d && \
          SPECTRO_LUET_VERSION=$SPECTRO_LUET_VERSION luet repo add spectro --type docker --url $SPECTRO_LUET_REPO/$LUET_REPO/$SPECTRO_LUET_VERSION --priority 1 -y
    
    COPY --if-exists spectro-luet-auth.yaml spectro-luet-auth.yaml
    RUN --no-cache if [ -f spectro-luet-auth.yaml ]; then cat spectro-luet-auth.yaml >> /etc/luet/repos.conf.d/spectro.yaml; fi
    RUN --no-cache luet repo update

    IF [ "$OS_DISTRIBUTION" = "rhel" ]
        RUN yum install -y openssl rsyslog logrotate
    END

    IF [ "$OS_DISTRIBUTION" = "sles" ]
        RUN if [ ! -e /usr/bin/apparmor_parser ]; then cp /sbin/apparmor_parser /usr/bin/apparmor_parser; fi
    END

    DO +OS_RELEASE --OS_VERSION=$KAIROS_VERSION

    RUN rm -rf /var/cache/* && \
        journalctl --vacuum-size=1K && \
        rm -rf /etc/machine-id && \
        rm -rf /var/lib/dbus/machine-id
    RUN touch /etc/machine-id && \ 
        chmod 444 /etc/machine-id
    RUN rm /tmp/* -rf

    IF [ "$DISABLE_SELINUX" = "true" ]
    # Ensure SElinux gets disabled
        RUN if grep "security=selinux" /etc/cos/bootargs.cfg > /dev/null; then sed -i 's/security=selinux //g' /etc/cos/bootargs.cfg; fi &&\
            if grep "selinux=1" /etc/cos/bootargs.cfg > /dev/null; then sed -i 's/selinux=1/selinux=0/g' /etc/cos/bootargs.cfg; fi
    END

# Used to build the installer image. The installer ISO will be created from this.
iso-image:
    FROM --platform=linux/${ARCH} +base-image
    IF [ "$IS_UKI" = "false" ]
        COPY --platform=linux/${ARCH} +stylus-image/ /
    ELSE
        COPY --platform=linux/${ARCH} +stylus-image/ /
        RUN find /opt/spectrocloud/bin/. ! -name 'agent-provider-stylus' -type f -exec rm -f {} +
        RUN rm -f /usr/bin/luet
    END
    COPY overlay/files/ /

    IF [ -f /etc/logrotate.d/stylus.conf ]
        RUN chmod 644 /etc/logrotate.d/stylus.conf
    END
    
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id

    SAVE IMAGE palette-installer-image:$IMAGE_TAG

iso-disk-image:
    BUILD +iso

    FROM scratch
    COPY +iso/*.iso /disk/
    SAVE IMAGE --push $ISO_DISK_IMG

go-deps:
    FROM $SPECTRO_PUB_REPO/golang:${GOLANG_VERSION}-alpine
    RUN apk add libc-dev binutils-gold clang


BUILD_GOLANG:
    COMMAND
    ARG WORKDIR=/build
    WORKDIR $WORKDIR

    ARG BIN
    ARG SRC
    ARG GOOS
    ARG GOARCH
    ARG VERSION=dev

    ENV GOOS=$GOOS 
    ENV GOARCH=$GOARCH
    ENV GO_LDFLAGS=" -X github.com/spectrocloud/stylus/pkg/version.Version=${VERSION} -w -s"

    ENV CC=clang
    RUN go mod download
    RUN go-build-static.sh -a -o ${BIN} ./${SRC}

    SAVE ARTIFACT ${BIN} ${BIN} AS LOCAL build/${BIN}

internal-slink:
    FROM +go-deps

    WORKDIR /build
    COPY internal internal

    ARG BUILD_DIR=/build/internal
    WORKDIR $BUILD_DIR
    
    DO +BUILD_GOLANG --BIN=slink --SRC=cmd/slink/slink.go --WORKDIR=$BUILD_DIR

    SAVE ARTIFACT slink

rust-deps:
    FROM rust:1.78-bookworm
    RUN apt-get update -qq
    RUN apt-get install --no-install-recommends -qq autoconf autotools-dev libtool-bin clang cmake bsdmainutils

build-efi-size-check:
    FROM +rust-deps

    WORKDIR /build
    COPY --keep-ts efi-size-check efi-size-check

    WORKDIR /build/efi-size-check
    RUN cargo build --target x86_64-unknown-uefi

    SAVE ARTIFACT target/x86_64-unknown-uefi/debug/efi-size-check.efi

iso-efi-size-check:
    FROM +ubuntu-systemd

    RUN apt-get update
    RUN apt-get install -y mtools xorriso

    WORKDIR /build

    COPY +build-efi-size-check/efi-size-check.efi /build/efi-size-check.efi
    RUN mkdir -p esp
    RUN dd if=/dev/urandom of=esp/ABC bs=1M count=$EFI_MAX_SIZE
    RUN dd if=/dev/zero of=fat.img bs=1M count=$EFI_IMG_SIZE
    RUN mformat -i fat.img -F ::
    RUN mmd -i fat.img ::/EFI
    RUN mmd -i fat.img ::/EFI/BOOT
    RUN mcopy -i fat.img efi-size-check.efi ::/EFI/BOOT/BOOTX64.EFI
    RUN mcopy -i fat.img esp/ABC ::
    RUN mkdir -p iso
    RUN cp fat.img iso
    RUN xorriso -as mkisofs -e fat.img -no-emul-boot -o efi-size-check.iso iso

    SAVE ARTIFACT efi-size-check.iso AS LOCAL ./build/

ubuntu-systemd:
    IF [ "$FIPS_ENABLED" = "true" ]
        ARG SYSTEMD_IMAGE=$SPECTRO_PUB_REPO/third-party/ubuntu-systemd-fips:20.04
    ELSE
        ARG SYSTEMD_IMAGE=$SPECTRO_PUB_REPO/third-party/ubuntu-systemd:22.04
    END
    FROM $SYSTEMD_IMAGE

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

download-third-party:
    ARG TARGETPLATFORM
    ARG binary
    FROM --platform=$TARGETPLATFORM $SPECTRO_PUB_REPO/builders/spectro-third-party:${BUILDER_3RDPARTY_VERSION}
    ARG TARGETARCH
    SAVE ARTIFACT /binaries/${binary}/latest/$BIN_TYPE/$TARGETARCH/${binary} ${binary}
    SAVE ARTIFACT /binaries/${binary}/latest/$BIN_TYPE/$TARGETARCH/${binary}.version ${binary}.version

third-party:
    DO +BASE_ALPINE
    ARG binary
    RUN apk add upx
    WORKDIR /WORKDIR

    COPY (+download-third-party/${binary} --binary=${binary}) /WORKDIR/${binary}
    COPY (+download-third-party/${binary}.version --binary=${binary}) /WORKDIR/${binary}.version

    DO +UPX --bin=/WORKDIR/${binary}

    SAVE ARTIFACT /WORKDIR/${binary} ${binary}
    SAVE ARTIFACT /WORKDIR/${binary}.version ${binary}.version

UPX:
    COMMAND
    ARG bin
    RUN upx -1 $bin
