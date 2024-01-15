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
ARG PE_VERSION=v4.2.1
ARG SPECTRO_LUET_VERSION=v1.2.0
ARG KAIROS_VERSION=v2.4.3
ARG K3S_FLAVOR_TAG=k3s1
ARG RKE2_FLAVOR_TAG=rke2r1
ARG BASE_IMAGE_URL=quay.io/kairos
ARG OSBUILDER_VERSION=v0.7.11
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
ARG TWO_NODE=false
ARG TWO_NODE_BACKEND=postgres
ARG KINE_VERSION=0.10.3
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

# Determine PG config dir (only relevant if TWO_NODE=true)
IF [ "$OS_DISTRIBUTION" = "ubuntu" ]
    IF [ "$TWO_NODE_BACKEND" = "postgres" ]
        ARG PG_CONF_DIR=/etc/postgresql/16/main
    END
ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
    IF [ "$TWO_NODE_BACKEND" = "postgres" ]
        ARG PG_CONF_DIR=/var/lib/pgsql/data
    END
END

IF [[ "$BASE_IMAGE" =~ "ubuntu-20-lts-arm-nvidia-jetson-agx-orin" ]]
    ARG IS_JETSON=true
END

elemental:
    FROM quay.io/kairos/packages:elemental-cli-system-0.3.1
    SAVE ARTIFACT /usr/bin/elemental /elemental

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

build-provider-images-fips:
    IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
       BUILD  +provider-image --K8S_VERSION=1.24.13
       BUILD  +provider-image --K8S_VERSION=1.25.9
       BUILD  +provider-image --K8S_VERSION=1.26.4
       BUILD  +provider-image --K8S_VERSION=1.27.2
    ELSE IF [ "$K8S_DISTRIBUTION" = "rke2" ]
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
    IF [ "$CLUSTERCONFIG" != ""]
        COPY --if-exists $CLUSTERCONFIG /overlay/opt/spectrocloud/clusterconfig/spc.tgz
    END
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
    COPY +stylus-image/etc/kairos/branding /etc/kairos/branding
    COPY +stylus-image/oem/stylus_config.yaml /etc/kairos/branding/stylus_config.yaml
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
    IF [ "$FIPS_ENABLED" = "true" ]
        ARG STYLUS_BASE=gcr.io/spectro-images-public/stylus-framework-fips-linux-$ARCH:$PE_VERSION
    ELSE
        ARG STYLUS_BASE=gcr.io/spectro-images-public/stylus-framework-linux-$ARCH:$PE_VERSION
    END
    FROM $STYLUS_BASE
    SAVE ARTIFACT ./*
    SAVE ARTIFACT /etc/kairos/branding
    SAVE ARTIFACT /oem/stylus_config.yaml

kairos-provider-image:
    IF [ "$K8S_DISTRIBUTION" = "kubeadm" ]
        ARG PROVIDER_BASE=gcr.io/spectro-dev-public/kairos-io/provider-kubeadm:$KUBEADM_PROVIDER_VERSION
    ELSE IF [ "$K8S_DISTRIBUTION" = "kubeadm-fips" ]
        ARG PROVIDER_BASE=gcr.io/spectro-dev-public/kairos-io/provider-kubeadm-fips:$KUBEADM_PROVIDER_VERSION
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

    # OS == Ubuntu
    IF [ "$OS_DISTRIBUTION" = "ubuntu" ] &&  [ "$ARCH" = "amd64" ]
        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /etc/ssl/certs
            RUN  update-ca-certificates
        END

        RUN apt update && \
            apt install --no-install-recommends zstd vim iputils-ping bridge-utils curl tcpdump ethtool -y
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

        RUN ln -s /usr/sbin/grub-editenv /usr/bin/grub2-editenv

        RUN rm -rf /var/cache/* && \
            apt clean

        IF $TWO_NODE
            IF [ "$TWO_NODE_BACKEND" = "postgres" ]
                RUN apt install -y apt-transport-https ca-certificates curl && \
                    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
                    curl -fsSL -o postgresql.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
                    gpg --batch --yes --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg postgresql.asc && \
                    rm postgresql.asc && \
                    apt update && \
                    apt install -y postgresql-16 postgresql-contrib-16 iputils-ping
            END
        END
            
    # OS == Opensuse
    ELSE IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ] && [ "$ARCH" = "amd64" ]
        # Add proxy certificate if present
        IF [ ! -z $PROXY_CERT_PATH ]
            COPY sc.crt /usr/share/pki/trust/anchors
            RUN update-ca-certificates
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

        IF $TWO_NODE
            IF [ $TWO_NODE_BACKEND = "postgres" ]
                RUN zypper --non-interactive --quiet addrepo --refresh -p 90 http://download.opensuse.org/repositories/server:database:postgresql/openSUSE_Tumbleweed/ PostgreSQL && \
                    zypper --gpg-auto-import-keys ref && \
                    zypper install -y postgresql-16 postgresql-server-16 postgresql-contrib iputils
            END
        END
        RUN zypper install -y zstd vim iputils bridge-utils curl ethtool tcpdump && \
            zypper cc && \
            zypper clean
    END

    IF [ "$OS_DISTRIBUTION" = "opensuse-leap" ]
        RUN zypper install -y apparmor-parser apparmor-profiles
        RUN zypper cc && \
            zypper clean
        RUN cp /sbin/apparmor_parser /usr/bin/apparmor_parser
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

    COPY +elemental/elemental /usr/bin/elemental

    # Ensure SElinux gets disabled
    RUN if grep "security=selinux" /etc/cos/bootargs.cfg > /dev/null; then sed -i 's/security=selinux //g' /etc/cos/bootargs.cfg; fi &&\
        if grep "selinux=1" /etc/cos/bootargs.cfg > /dev/null; then sed -i 's/selinux=1/selinux=0/g' /etc/cos/bootargs.cfg; fi

    IF $TWO_NODE
        RUN mkdir -p /opt/spectrocloud/bin && \
            curl -L https://github.com/k3s-io/kine/releases/download/v${KINE_VERSION}/kine-amd64 | install -m 755 /dev/stdin /opt/spectrocloud/bin/kine

        IF [ $TWO_NODE_BACKEND = "postgres" ]
            RUN sed -i '/^#wal_level = replica/ s/#wal_level = replica/wal_level = logical/' "${PG_CONF_DIR}"/postgresql.conf && \
                sed -i '/^#max_worker_processes = 8/ s/#max_worker_processes = 8/max_worker_processes = 16/' ${PG_CONF_DIR}/postgresql.conf && \
                sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" ${PG_CONF_DIR}/postgresql.conf && \
                echo "host all all 0.0.0.0/0 md5" | tee -a ${PG_CONF_DIR}/pg_hba.conf && \
                su postgres -c 'echo "export PERL5LIB=/usr/share/perl/5.34:/usr/share/perl5:/usr/lib/x86_64-linux-gnu/perl/5.34" > ~/.bash_profile' && \
                systemctl enable postgresql
        END
    END

# Used to build the installer image.  The installer ISO will be created from this.
iso-image:
    FROM --platform=linux/${ARCH} +base-image
    COPY --platform=linux/${ARCH} +stylus-image/ /
    COPY overlay/files/ /
    
    RUN rm -f /etc/ssh/ssh_host_* /etc/ssh/moduli
    RUN touch /etc/machine-id \
        && chmod 444 /etc/machine-id
    SAVE IMAGE palette-installer-image:$PE_VERSION-$CUSTOM_TAG

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

    # update OS-release file
    RUN sed -i -n '/KAIROS_/!p' /etc/os-release
    RUN envsubst >>/etc/os-release </usr/lib/os-release.tmpl
