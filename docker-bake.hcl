variable "FIPS_ENABLED" {
  type = bool
  default = false
}

variable "ARCH" {
  default = "amd64"
}

variable "SPECTRO_PUB_REPO" {
  default = FIPS_ENABLED ? "us-east1-docker.pkg.dev/spectro-images-fips/dev/piyush" : "us-east1-docker.pkg.dev/spectro-images/dev/piyush"
}

variable "SPECTRO_THIRD_PARTY_IMAGE" {
  default = "us-east1-docker.pkg.dev/spectro-images/third-party/spectro-third-party:4.6"
}

variable "ALPINE_TAG" {
  default = "3.20"
}

variable "ALPINE_IMG" {
  default = "${SPECTRO_PUB_REPO}/edge/canvos/alpine:${ALPINE_TAG}"
}

variable "SPECTRO_LUET_REPO" {
  default = "us-docker.pkg.dev/palette-images/edge"
}

variable "LUET_PROJECT" {
  default = "luet-repo"
}

variable "PE_VERSION" {
  default = "v4.6.21"
}

variable "SPECTRO_LUET_VERSION" {
  default = "v4.7.0-rc.1"
}

variable "KAIROS_VERSION" {
  default = "v3.4.2"
}

variable AURORABOOT_IMAGE {
  default = "quay.io/kairos/auroraboot:v0.10.0"
}

variable "K3S_PROVIDER_VERSION" {
  default = "v4.6.0"
}

variable "KUBEADM_PROVIDER_VERSION" {
  default = "v4.6.3"
}

variable "RKE2_PROVIDER_VERSION" {
  default = "v4.6.0"
}

variable "NODEADM_PROVIDER_VERSION" {
  default = "v4.6.0"
}

variable "CANONICAL_PROVIDER_VERSION" {
  default = "v1.1.0-rc.1"
}

variable "K3S_FLAVOR_TAG" {
  default = "k3s1"
}

variable "RKE2_FLAVOR_TAG" {
  default = "rke2r1"
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

variable KINE_VERSION {
  default = "0.11.4"
}

variable "TWO_NODE" {
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

variable "CMDLINE" {
  default = "stylus.registration"
}

variable "BRANDING" {
  default = "Palette eXtended Kubernetes Edge"
}

variable "DEBUG" {
  type = bool
  default = false
}

variable "UKI_BRING_YOUR_OWN_KEYS" {
  type = bool
  default = false
}

variable "MY_ORG" {
  default = "ACME Corp"
}

variable "EXPIRATION_IN_DAYS" {
  default = 5475
}

variable "CMDLINE" {
  default = "stylus.registration"
}

variable "BRANDING" {
  default = "Palette eXtended Kubernetes Edge"
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

variable "BASE_IMAGE" {
  default = ""
}

variable "OSBUILDER_IMAGE" {}

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

# secret "enrollment" {
#   type = "file"
#   src = "secure-boot/enrollment/"
# }

# secret "private-keys" {
#   type = "file"
#   src = "secure-boot/private-keys/"
# }

# secret "public-keys" {
#   type = "file"
#   src = "secure-boot/public-keys/"
# }

function "get_base_image" {
  params = [base_image, os_distribution, os_version, is_uki]
  result = base_image != "" ? base_image : (
    
    os_distribution == "ubuntu" && ( os_version == "20" || os_version == "20.04" ) ? 
    "${SPECTRO_PUB_REPO}/edge/kairos-${OS_DISTRIBUTION}:${OS_VERSION}.04-core-${ARCH}-generic-${KAIROS_VERSION}" :

    os_distribution == "ubuntu" && ( os_version == "22" || os_version == "22.04" ) ? 
      "${SPECTRO_PUB_REPO}/edge/kairos-${OS_DISTRIBUTION}:${OS_VERSION}.04-core-${ARCH}-generic-${KAIROS_VERSION}" :
    
    os_distribution == "ubuntu" && ( os_version == "24" || os_version == "24.04" ) ? 
      "${SPECTRO_PUB_REPO}/edge/kairos-${OS_DISTRIBUTION}:${OS_VERSION}.04-core-${ARCH}-generic-${KAIROS_VERSION}" :

    os_distribution == "ubuntu" && ( os_version == "24" || os_version == "24.04" ) && is_uki ? 
      "${SPECTRO_PUB_REPO}/edge/kairos-${OS_DISTRIBUTION}:${OS_VERSION}.04-core-${ARCH}-generic-${KAIROS_VERSION}-uki" :

    os_distribution == "opensuse" && os_version == "15.6" ? 
      "${SPECTRO_PUB_REPO}/edge/kairos-opensuse:leap-${OS_VERSION}-core-${ARCH}-generic-${KAIROS_VERSION}" :
    
    ""
  )
}

target "stylus-image" {
  dockerfile = "dockerfiles/Dockerfile.stylus-image"
  target = "stylus-image"
  args = {
    STYLUS_BASE = STYLUS_BASE
    ARCH = ARCH
  }
  platforms = ["linux/${ARCH}"]
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
    UBUNTU_PRO_KEY = UBUNTU_PRO_KEY
    UPDATE_KERNEL = UPDATE_KERNEL
    CIS_HARDENING = CIS_HARDENING
    KAIROS_VERSION = KAIROS_VERSION
    DISABLE_SELINUX = DISABLE_SELINUX
    ARCH = ARCH
  }
}

function "get_provider_base" {
  params = [k8s_distribution, spectro_pub_repo, kubeadm_version, k3s_version, rke2_version, nodeadm_version, canonical_version]
  result = (
    k8s_distribution == "kubeadm" ? "${spectro_pub_repo}/edge/kairos-io/provider-kubeadm:${kubeadm_version}" :
    k8s_distribution == "kubeadm-fips" ? "${spectro_pub_repo}/edge/kairos-io/provider-kubeadm:${kubeadm_version}" :
    k8s_distribution == "k3s" ? "${spectro_pub_repo}/edge/kairos-io/provider-k3s:${k3s_version}" :
    k8s_distribution == "rke2" ? "${spectro_pub_repo}/edge/kairos-io/provider-rke2:${rke2_version}" :
    k8s_distribution == "nodeadm" ? "${spectro_pub_repo}/edge/kairos-io/provider-nodeadm:${nodeadm_version}" :
    k8s_distribution == "canonical" ? "${spectro_pub_repo}/edge/kairos-io/provider-canonical:${canonical_version}" :
    ""
  )
}

target "kairos-provider-image" {
  dockerfile = "dockerfiles/Dockerfile.kairos-provider-image"
  target = "kairos-provider-image"
  platforms = ["linux/${ARCH}"]
  args = {
    PROVIDER_BASE = get_provider_base(
      K8S_DISTRIBUTION,
      SPECTRO_PUB_REPO,
      KUBEADM_PROVIDER_VERSION,
      K3S_PROVIDER_VERSION,
      RKE2_PROVIDER_VERSION,
      NODEADM_PROVIDER_VERSION,
      CANONICAL_PROVIDER_VERSION,
    )
  }
}

target "install-k8s" {
  dockerfile = "dockerfiles/Dockerfile.install-k8s"
  target = "install-k8s"
  platforms = ["linux/${ARCH}"]
  contexts = {
    third-party-luet = "target:third-party-luet"
  }
  args = {
    BASE_ALPINE_IMAGE = ALPINE_IMG
    ARCH = ARCH
    K8S_DISTRIBUTION = K8S_DISTRIBUTION
    K8S_VERSION = K8S_VERSION
    K3S_FLAVOR_TAG = K3S_FLAVOR_TAG
    RKE2_FLAVOR_TAG = RKE2_FLAVOR_TAG
    LUET_PROJECT = LUET_PROJECT
    LUET_REPO = ARCH == "arm64" ? "${LUET_PROJECT}-arm" : LUET_PROJECT
    SPECTRO_LUET_REPO = SPECTRO_LUET_REPO
    SPECTRO_LUET_VERSION = SPECTRO_LUET_VERSION
  }
}

target "provider-image" {
  dockerfile = "dockerfiles/Dockerfile.provider-image"
  target = "provider-image"
  platforms = ["linux/${ARCH}"]
  contexts = {
    base-image = "target:base-image"
    kairos-provider-image = "target:kairos-provider-image"
    stylus-image = "target:stylus-image"
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
  # secret = ["enrollment", "private-keys", "public-keys"]
  secret = [
    {
      type = "file"
      src = "secure-boot/enrollment/"
      id = "enrollment"
    },
    {
      type = "file"
      src = "secure-boot/private-keys/"
      id = "private-keys"
    },
    {
      type = "file"
      src = "secure-boot/public-keys/"
      id = "public-keys"
    }
  ]
  args = {
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
  }
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
    stylus-image = "target:stylus-image"
  }
  args = {
    ARCH = ARCH
    IS_UKI = IS_UKI
  }
  tags = ["palette-installer-image:${IMAGE_TAG}"]
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
    CONTAINER_IMAGE = "palette-installer-image:${IMAGE_TAG}"
  }
  output = ["type=local,dest=./build"]
}

target "build-uki-iso" {
  dockerfile = "dockerfiles/Dockerfile.build-uki-iso"
  target = "output"
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
  # secret = ["enrollment", "private-keys", "public-keys"]
  secret = [
    {
      type = "file"
      src = "secure-boot/enrollment/"
      id = "enrollment"
    },
    {
      type = "file"
      src = "secure-boot/private-keys/"
      id = "private-keys"
    },
    {
      type = "file"
      src = "secure-boot/public-keys/"
      id = "public-keys"
    }
  ]
  output = ["type=local,dest=./iso-output/"]
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
  target = "output"
  platforms = ["linux/${ARCH}"]
  contexts = UKI_BRING_YOUR_OWN_KEYS ? {
    uki-byok = "target:uki-byok"
  } : {}
  args = {
    MY_ORG = MY_ORG
    EXPIRATION_IN_DAYS = EXPIRATION_IN_DAYS
    UKI_BRING_YOUR_OWN_KEYS = UKI_BRING_YOUR_OWN_KEYS
    INCLUDE_MS_SECUREBOOT_KEYS = INCLUDE_MS_SECUREBOOT_KEYS
    AURORABOOT_IMAGE = AURORABOOT_IMAGE
    ARCH = ARCH
  }
  output = ["type=local,dest=./secure-boot/"]
}

target "uki-byok" {
  dockerfile = "dockerfiles/Dockerfile.uki-byok"
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
  tags = ["internal-slink:latest"]
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
    # build-iso = "target:build-iso"
  }
  tags = ["${IMAGE_REGISTRY}/${IMAGE_REPO}/${ISO_NAME}:${IMAGE_TAG}"]
  output = ["type=image,push=true"]
}
