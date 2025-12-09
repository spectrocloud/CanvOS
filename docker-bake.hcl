variable "FIPS_ENABLED" {
  type = bool
  default = false
}

variable "ARCH" {
  default = "amd64"
}

variable "SPECTRO_PUB_REPO" {
  default = FIPS_ENABLED ? "us-east1-docker.pkg.dev/spectro-images/dev-fips/arun" : "us-east1-docker.pkg.dev/spectro-images/dev/arun"
}

variable "SPECTRO_THIRD_PARTY_IMAGE" {
  default = "us-east1-docker.pkg.dev/spectro-images/third-party/spectro-third-party:4.6"
}

variable "ALPINE_TAG" {
  default = "3.22"
}

variable "ALPINE_IMG" {
  default = "${SPECTRO_PUB_REPO}/edge/canvos/alpine:${ALPINE_TAG}"
}

variable "SPECTRO_LUET_REPO" {
  default = "us-docker.pkg.dev/palette-images/edge"
}

variable "KAIROS_BASE_IMAGE_URL" {
  default = "${SPECTRO_PUB_REPO}/edge"
}

variable AURORABOOT_IMAGE {
  default = "quay.io/kairos/auroraboot:v0.14.0"
}

variable "PE_VERSION" {
  default = "v4.8.1"
}

variable "KAIROS_VERSION" {
  default = "v3.5.9"
}

variable "K3S_FLAVOR_TAG" {
  default = "k3s1"
}

variable "RKE2_FLAVOR_TAG" {
  default = "rke2r1"
}

variable "K3S_PROVIDER_VERSION" {
  default = "v4.7.1"
}

variable "KUBEADM_PROVIDER_VERSION" {
  default = "v4.7.3"
}

variable "RKE2_PROVIDER_VERSION" {
  default = "v4.7.1"
}

variable "NODEADM_PROVIDER_VERSION" {
  default = "v4.6.0"
}

variable "CANONICAL_PROVIDER_VERSION" {
  default = "v1.2.2"
}


variable OS_DISTRIBUTION {}
variable OS_VERSION {}

variable K8S_DISTRIBUTION {}
variable K8S_VERSION {}

variable IMAGE_REGISTRY {}
variable IMAGE_REPO {
  default = OS_DISTRIBUTION
}

variable "ISO_NAME" {
  default = "installer"
}

variable "CLUSTERCONFIG" {}

variable EDGE_CUSTOM_CONFIG {
  default = ".edge-custom-config.yaml"
}

variable "CUSTOM_TAG" {}

variable "DISABLE_SELINUX" {
  type = bool
  default = true
}

variable "CIS_HARDENING" {
  type = bool
  default = false
}

variable UBUNTU_PRO_KEY {}

variable DRBD_VERSION {
  default = "9.2.13"
}

variable HTTP_PROXY {}
variable HTTPS_PROXY {}
variable NO_PROXY {}
variable PROXY_CERT_PATH {}

variable http_proxy {
  default = HTTP_PROXY
}
variable https_proxy {
  default = HTTPS_PROXY
}
variable no_proxy {
  default = NO_PROXY
}

variable "UPDATE_KERNEL" {
  type = bool
  default = false
}

variable ETCD_VERSION {
  default = "v3.5.13"
}

variable KINE_VERSION {
  default = "0.11.4"
}

variable "TWO_NODE" {
  type = bool
  default = false
}

variable "IS_MAAS" {
  type = bool
  default = false
}

variable "IS_UKI" {
  type = bool
  default = false
}

variable "INCLUDE_MS_SECUREBOOT_KEYS" {
  type = bool
  default = true
}

variable "AUTO_ENROLL_SECUREBOOT_KEYS" {
  type = bool
  default = false
}

variable "UKI_BRING_YOUR_OWN_KEYS" {
  type = bool
  default = false
}

variable "CMDLINE" {
  default = "stylus.registration"
}

variable "BRANDING" {
  default = "Palette eXtended Kubernetes Edge"
}

variable "FORCE_INTERACTIVE_INSTALL"{
  type = bool
  default = false
}

variable "MY_ORG" {
  default = "ACME Corp"
}

variable "EXPIRATION_IN_DAYS" {
  default = 5475
}

variable "EFI_MAX_SIZE" {
  default = "2048"
}

variable "EFI_IMG_SIZE" {
  default = "2200"
}

variable "GOLANG_VERSION" {
  default = "1.23"
}

variable "IS_CLOUD_IMAGE" {
  type = bool
  default = false
}


variable "DEBUG" {
  type = bool
  default = false
}

variable "BASE_IMAGE" {
  default = ""
}

variable "REGION" {}

variable "S3_BUCKET" {}

variable "S3_KEY" {}

# Alpine base image provided by platform team
variable "ALPINE_BASE_IMAGE" {
  default = FIPS_ENABLED ? "us-docker.pkg.dev/palette-images-fips/third-party/alpine:${ALPINE_TAG}-fips" : "us-docker.pkg.dev/palette-images/third-party/alpine:${ALPINE_TAG}"
}

# Secrets for secure boot private keys - used by trustedboot-image and build-uki-iso
variable "SECURE_BOOT_SECRETS" {
  default = [
    "id=db_key,src=secure-boot/private-keys/db.key",
    "id=db_pem,src=secure-boot/public-keys/db.pem",
    "id=kek_key,src=secure-boot/private-keys/KEK.key",
    "id=kek_pem,src=secure-boot/public-keys/KEK.pem",
    "id=pk_key,src=secure-boot/private-keys/PK.key",
    "id=pk_pem,src=secure-boot/public-keys/PK.pem",
    "id=tpm2_pcr_private,src=secure-boot/private-keys/tpm2-pcr-private.pem"
  ]
}

variable "IS_JETSON" {
  type = bool
  default = length(regexall("nvidia-jetson-agx-orin", BASE_IMAGE)) > 0
}

variable "STYLUS_BASE" {
  default = "${SPECTRO_PUB_REPO}/edge/stylus-framework-linux-${ARCH}:${PE_VERSION}"
}

variable "STYLUS_PACKAGE_BASE" {
  default = "${SPECTRO_PUB_REPO}/edge/stylus-linux-${ARCH}:${PE_VERSION}"
}

variable "BIN_TYPE" {
  default = FIPS_ENABLED ? "vertex" : "palette"
}

variable "CLI_IMAGE" {
  default = FIPS_ENABLED ? "${SPECTRO_PUB_REPO}/edge/palette-edge-cli-fips-${ARCH}:${PE_VERSION}" : "${SPECTRO_PUB_REPO}/edge/palette-edge-cli-${ARCH}:${PE_VERSION}"
}

variable "IMAGE_TAG" {
  default = CUSTOM_TAG != "" ? "${PE_VERSION}-${CUSTOM_TAG}" : PE_VERSION
}

variable "IMAGE_PATH" {
  default = "${IMAGE_REGISTRY}/${IMAGE_REPO}:${K8S_DISTRIBUTION}-${K8S_VERSION}-${IMAGE_TAG}"
}

function "get_ubuntu_image" {
  params = [fips_enabled, spectro_pub_repo]
  result = fips_enabled ? "${spectro_pub_repo}/third-party/ubuntu-fips:22.04" : "${spectro_pub_repo}/third-party/ubuntu:22.04"
}

function "get_base_image" {
  params = [base_image, os_distribution, os_version, is_uki]
  result = base_image != "" ? base_image : (
    # Format version: add .04 if not present, then build image URL
    os_distribution == "ubuntu" && length(regexall("^(20|22|24)(\\.04)?$", os_version)) > 0 ? 
      "${KAIROS_BASE_IMAGE_URL}/kairos-${OS_DISTRIBUTION}:${length(regexall("\\.04", os_version)) > 0 ? os_version : os_version + ".04"}-core-${ARCH}-generic-${KAIROS_VERSION}${is_uki && length(regexall("^24", os_version)) > 0 ? "-uki" : ""}" :

    os_distribution == "opensuse-leap" && os_version == "15.6" ? 
      "${KAIROS_BASE_IMAGE_URL}/kairos-opensuse:leap-${OS_VERSION}-core-${ARCH}-generic-${KAIROS_VERSION}" :
    
    ""
  )
}


target "base" {
  dockerfile = "Dockerfile"
  args = {
    BASE = get_base_image(BASE_IMAGE, OS_DISTRIBUTION, OS_VERSION, IS_UKI)
    OS_DISTRIBUTION = OS_DISTRIBUTION
    PROXY_CERT_PATH = PROXY_CERT_PATH
    HTTP_PROXY = HTTP_PROXY
    HTTPS_PROXY = HTTPS_PROXY
    NO_PROXY = NO_PROXY
    DRBD_VERSION = DRBD_VERSION
  }
}

target "base-image" {
  dockerfile = "dockerfiles/Dockerfile.base-image"
  contexts = {
    base = "target:base"
  }
  args = {
    OS_DISTRIBUTION = OS_DISTRIBUTION
    OS_VERSION = OS_VERSION
    IS_JETSON = IS_JETSON
    IS_UKI = IS_UKI
    UPDATE_KERNEL = UPDATE_KERNEL
    CIS_HARDENING = CIS_HARDENING
    KAIROS_VERSION = KAIROS_VERSION
    DISABLE_SELINUX = DISABLE_SELINUX
    ARCH = ARCH
    FIPS_ENABLED = FIPS_ENABLED
    IS_MAAS = IS_MAAS
  }
  secret = ["id=ubuntu_pro_key,env=UBUNTU_PRO_KEY"]
}

function "get_provider_base" {
  params = [k8s_distribution, spectro_pub_repo, kubeadm_version, k3s_version, rke2_version, nodeadm_version, canonical_version]
  result = (
    k8s_distribution == "kubeadm" ? "docker-image://${spectro_pub_repo}/edge/kairos-io/provider-kubeadm:${kubeadm_version}" :
    k8s_distribution == "kubeadm-fips" ? "docker-image://${spectro_pub_repo}/edge/kairos-io/provider-kubeadm:${kubeadm_version}" :
    k8s_distribution == "k3s" ? "docker-image://${spectro_pub_repo}/edge/kairos-io/provider-k3s:${k3s_version}" :
    k8s_distribution == "rke2" ? "docker-image://${spectro_pub_repo}/edge/kairos-io/provider-rke2:${rke2_version}" :
    k8s_distribution == "nodeadm" ? "docker-image://${spectro_pub_repo}/edge/kairos-io/provider-nodeadm:${nodeadm_version}" :
    k8s_distribution == "canonical" ? "docker-image://${spectro_pub_repo}/edge/kairos-io/provider-canonical:${canonical_version}" :
    ""
  )
}

target "install-k8s" {
  dockerfile = "dockerfiles/Dockerfile.install-k8s"
  target = "install-k8s"
  platforms = ["linux/${ARCH}"]
  contexts = {
    third-party-luet = "target:third-party-luet"
  }
  args = {
    ALPINE_IMG = ALPINE_IMG
    ARCH = ARCH
    K8S_DISTRIBUTION = K8S_DISTRIBUTION
    K8S_VERSION = K8S_VERSION
    K3S_FLAVOR_TAG = K3S_FLAVOR_TAG
    RKE2_FLAVOR_TAG = RKE2_FLAVOR_TAG
    LUET_REPO = ARCH == "arm64" ? "luet-repo-arm" : "luet-repo-amd"
    SPECTRO_LUET_REPO = SPECTRO_LUET_REPO
  }
}

target "provider-image" {
  dockerfile = "dockerfiles/Dockerfile.provider-image"
  target = "provider-image"
  platforms = ["linux/${ARCH}"]
  contexts = {
    base-image = "target:base-image"
    // kairos-provider-image = "target:kairos-provider-image"
    kairos-provider-image = get_provider_base(
      K8S_DISTRIBUTION,
      SPECTRO_PUB_REPO,
      KUBEADM_PROVIDER_VERSION,
      K3S_PROVIDER_VERSION,
      RKE2_PROVIDER_VERSION,
      NODEADM_PROVIDER_VERSION,
      CANONICAL_PROVIDER_VERSION,
    )
    stylus-image = "docker-image://${STYLUS_BASE}"
    install-k8s = "target:install-k8s"
    third-party-luet = "target:third-party-luet"
    third-party-etcdctl = "target:third-party-etcdctl"
    internal-slink = "target:internal-slink"
  }
  args = {
    ARCH = ARCH
    IMAGE_REPO = IMAGE_REPO
    K8S_DISTRIBUTION = K8S_DISTRIBUTION
    K8S_VERSION = K8S_VERSION
    K3S_FLAVOR_TAG = K3S_FLAVOR_TAG
    RKE2_FLAVOR_TAG = RKE2_FLAVOR_TAG
    OS_DISTRIBUTION = OS_DISTRIBUTION
    EDGE_CUSTOM_CONFIG = EDGE_CUSTOM_CONFIG
    TWO_NODE = TWO_NODE
    KINE_VERSION = KINE_VERSION
    IMAGE_PATH = IMAGE_PATH
    IS_UKI = IS_UKI
    UPDATE_KERNEL = UPDATE_KERNEL
  }
  tags = [IMAGE_PATH]
  output = ["type=image,push=true"]
}

target "uki-provider-image" {
  dockerfile = "dockerfiles/Dockerfile.uki-provider-image"
  platforms = ["linux/${ARCH}"]
  contexts = {
    third-party-luet = "target:third-party-luet"
    install-k8s = "target:install-k8s"
    trustedboot-image = "target:trustedboot-image"
    stylus-image = "docker-image://${STYLUS_BASE}"
  }
  args = {
    BASE_IMAGE = get_base_image(BASE_IMAGE, OS_DISTRIBUTION, OS_VERSION, IS_UKI)
    UBUNTU_IMAGE = get_ubuntu_image(FIPS_ENABLED, SPECTRO_PUB_REPO)
    EDGE_CUSTOM_CONFIG = EDGE_CUSTOM_CONFIG
    IMAGE_PATH = IMAGE_PATH
  }
  tags = [IMAGE_PATH]
  output = ["type=image,push=true"]
}

target "trustedboot-image" {
  dockerfile = "dockerfiles/Dockerfile.trustedboot-image"
  platforms = ["linux/${ARCH}"]
  target = "output"
  context = "."
  contexts = {
    provider-image = "target:provider-image"
  }
  args = {
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
    DEBUG = DEBUG
  }
  secret = SECURE_BOOT_SECRETS
  output = ["type=local,dest=./trusted-boot/"]
}

target "validate-user-data" {
  dockerfile = "dockerfiles/Dockerfile.validate-ud"
  target = "validate-user-data"
  args = {
    CLI_IMAGE = CLI_IMAGE
    ARCH = ARCH
  }
  platforms = ["linux/${ARCH}"]
}


target "iso-image" {
  dockerfile = "dockerfiles/Dockerfile.iso-image"
  target = "iso-image"
  platforms = ["linux/${ARCH}"]
  contexts = {
    base-image = "target:base-image"
    stylus-image = "docker-image://${STYLUS_BASE}"
  }
  args = {
    ARCH = ARCH
    IS_UKI = IS_UKI
    IS_CLOUD_IMAGE = IS_CLOUD_IMAGE
  }
  # MAAS uses latest tag, non-MAAS uses version tag
  tags = IS_MAAS ? ["palette-installer-image:latest"] : ["palette-installer-image:${IMAGE_TAG}"]
  output = ["type=docker"]
}

target "build-iso" {
  dockerfile = "dockerfiles/Dockerfile.build-iso"
  platforms = ["linux/${ARCH}"]
  target = "output"
  contexts = {
    validate-user-data = "target:validate-user-data"
    iso-image = "target:iso-image"
  }
  args = {
    ARCH = ARCH
    ISO_NAME = ISO_NAME
    CLUSTERCONFIG = CLUSTERCONFIG
    EDGE_CUSTOM_CONFIG = EDGE_CUSTOM_CONFIG
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
    FORCE_INTERACTIVE_INSTALL = FORCE_INTERACTIVE_INSTALL
  }
  output = ["type=local,dest=./build"]
}

target "build-uki-iso" {
  dockerfile = "dockerfiles/Dockerfile.build-uki-iso"
  target = "output"
  context = "."
  platforms = ["linux/${ARCH}"]
  contexts = {
    validate-user-data = "target:validate-user-data"
    stylus-image-pack = "target:stylus-image-pack"
    third-party-luet = "target:third-party-luet"
    iso-image = "target:iso-image"
  }
  args = {
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
    ARCH = ARCH
    ISO_NAME = ISO_NAME
    CLUSTERCONFIG = CLUSTERCONFIG
    EDGE_CUSTOM_CONFIG = EDGE_CUSTOM_CONFIG
    AUTO_ENROLL_SECUREBOOT_KEYS = AUTO_ENROLL_SECUREBOOT_KEYS
    DEBUG = DEBUG
    CMDLINE = CMDLINE
    BRANDING = BRANDING
  }
  secret = SECURE_BOOT_SECRETS
  output = ["type=local,dest=./build/"]
}

target "stylus-image-pack" {
  dockerfile = "dockerfiles/Dockerfile.stylus-image-pack"
  target = "output"
  platforms = ["linux/${ARCH}"]
  contexts = {
    third-party-luet = "target:third-party-luet"
  }
  args = {
    STYLUS_PACKAGE_BASE = STYLUS_PACKAGE_BASE
    STYLUS_BASE = STYLUS_BASE
    ARCH = ARCH
  }
  output = ["type=local,dest=./build/"]
}

target "uki-genkey" {
  dockerfile = "dockerfiles/Dockerfile.uki-genkey"
  context = "."
  target = UKI_BRING_YOUR_OWN_KEYS ? "output-byok" : "output-no-byok"
  platforms = ["linux/${ARCH}"]
  contexts = UKI_BRING_YOUR_OWN_KEYS ? {
    uki-byok = "target:uki-byok"
  } : {}
  args = {
    MY_ORG = MY_ORG
    EXPIRATION_IN_DAYS = EXPIRATION_IN_DAYS
    INCLUDE_MS_SECUREBOOT_KEYS = INCLUDE_MS_SECUREBOOT_KEYS
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
    ARCH = ARCH
  }
  output = ["type=local,dest=./secure-boot/"]
}

target "uki-byok" {
  dockerfile = "dockerfiles/Dockerfile.uki-byok"
  context = "."
  platforms = ["linux/${ARCH}"]
  args = {
    UBUNTU_IMAGE = get_ubuntu_image(FIPS_ENABLED, SPECTRO_PUB_REPO)
    INCLUDE_MS_SECUREBOOT_KEYS = INCLUDE_MS_SECUREBOOT_KEYS
  }
}

target "internal-slink" {
  dockerfile = "dockerfiles/Dockerfile.slink"
  context = "."
  args = {
    SPECTRO_PUB_REPO = SPECTRO_PUB_REPO
    GOLANG_VERSION = GOLANG_VERSION
    BIN = "slink"
    SRC = "cmd/slink/slink.go"
    GOOS = "linux"
    GOARCH = "amd64"
  }
  output = ["type=local,dest=build"]
}

target "third-party-luet" {
  dockerfile = "dockerfiles/Dockerfile.third-party"
  target = "third-party"
  args = {
    SPECTRO_THIRD_PARTY_IMAGE = SPECTRO_THIRD_PARTY_IMAGE
    ALPINE_IMG = ALPINE_IMG
    binary = "luet"
    BIN_TYPE = BIN_TYPE
    ARCH = ARCH
    TARGETPLATFORM = "linux/${ARCH}"
  }
}

target "third-party-etcdctl" {
  dockerfile = "dockerfiles/Dockerfile.third-party"
  target = "third-party"
  args = {
    SPECTRO_THIRD_PARTY_IMAGE = SPECTRO_THIRD_PARTY_IMAGE
    ALPINE_IMG = ALPINE_IMG
    binary = "etcdctl"
    BIN_TYPE = BIN_TYPE
    ARCH = ARCH
    TARGETPLATFORM = "linux/${ARCH}"
  }
}

target "iso-disk-image" {
  dockerfile = "dockerfiles/Dockerfile.iso-disk-image"
  platforms = ["linux/${ARCH}"]
  contexts = {
    build-iso = IS_UKI ? "target:build-uki-iso" : "target:build-iso"
  }
  tags = ["${IMAGE_REGISTRY}/${IMAGE_REPO}/${ISO_NAME}:${IMAGE_TAG}"]
  output = ["type=image,push=true"]
}

target "alpine-all" {
  dockerfile = "dockerfiles/Dockerfile.alpine"
  platforms = ["linux/amd64", "linux/arm64"]
  args = {
    ALPINE_BASE_IMAGE = ALPINE_BASE_IMAGE
  }
  tags = [ALPINE_IMG]
  output = ["type=image,push=true"]
}

target "iso-efi-size-check" {
  dockerfile = "dockerfiles/Dockerfile.iso-efi-size-check"
  context = "."
  target = "output"
  platforms = ["linux/amd64"]
  args = {
    UBUNTU_IMAGE = get_ubuntu_image(FIPS_ENABLED, SPECTRO_PUB_REPO)
    EFI_MAX_SIZE = EFI_MAX_SIZE
    EFI_IMG_SIZE = EFI_IMG_SIZE
  }
  output = ["type=local,dest=./build/"]
}

target "cloud-image" {
  dockerfile = "dockerfiles/Dockerfile.cloud-image"
  context = "."
  target = "output"
  platforms = ["linux/${ARCH}"]
  contexts = {
    iso-image = "target:iso-image"
  }
  args = {
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
    ARCH = ARCH
  }
  output = ["type=local,dest=./build/"]
}

target "aws-cloud-image" {
  dockerfile = "dockerfiles/Dockerfile.aws-cloud-image"
  context = "."
  target = "output"
  platforms = ["linux/${ARCH}"]
  contexts = {
    cloud-image = "target:cloud-image"
  }
  args = {
    UBUNTU_IMAGE = get_ubuntu_image(FIPS_ENABLED, SPECTRO_PUB_REPO)
    REGION = REGION
    S3_BUCKET = S3_BUCKET
    S3_KEY = S3_KEY
  }
  secret = [
    "id=AWS_PROFILE,env=AWS_PROFILE",
    "id=AWS_ACCESS_KEY_ID,env=AWS_ACCESS_KEY_ID",
    "id=AWS_SECRET_ACCESS_KEY,env=AWS_SECRET_ACCESS_KEY"
  ]
  output = ["type=local,dest=./build/"]
}
