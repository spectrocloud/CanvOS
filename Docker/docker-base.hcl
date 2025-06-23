variable "STYLUS_BASE" {
  default = "stylus-base:latest"  # Update with actual value
}

variable "TARGETARCH" {
  default = "amd64"
  validation {
    condition = TARGETARCH != ""
    error_message = "The variable 'TARGETARCH' must not be empty."
  }
}

variable "CLI_IMAGE" {
  default = "cli:latest"
}

target "validate-user-data" {
  dockerfile = "Dockerfile.validate-ud"
  target = "validate-user-data"
  args = {
    CLI_IMAGE = CLI_IMAGE
    TARGETARCH = TARGETARCH
  }
  platforms = ["linux/${TARGETARCH}"]
}

target "stylus-image" {
  dockerfile = "Dockerfile.stylus-image"
  target = "stylus-image"
  args = {
    STYLUS_BASE = STYLUS_BASE
    TARGETARCH = TARGETARCH
  }
  platforms = ["linux/${TARGETARCH}"]
}

target "base-certs" {
  dockerfile = "Dockerfile.certs"
  args = {
    BASE = BASE_IMAGE
    OS_DISTRIBUTION = OS_DISTRIBUTION
    PROXY_CERT_PATH = ""
    HTTP_PROXY = HTTP_PROXY
    HTTPS_PROXY = HTTPS_PROXY
    NO_PROXY = NO_PROXY
  }
}

target "base-image" {
  dockerfile = "Dockerfile.base-image"
  target = "base-with-certs"
  contexts = {
    base-certs = "target:base-certs"
  }
  depends-on = ["base-certs", "os-release"]
  args = {
    BASE_IMAGE = BASE_IMAGE
    OS_DISTRIBUTION = OS_DISTRIBUTION
    OS_VERSION = OS_VERSION
    HTTP_PROXY = HTTP_PROXY
    HTTPS_PROXY = HTTPS_PROXY
    NO_PROXY = NO_PROXY
    PROXY_CERT_PATH = ""
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

target "iso-image" {
  dockerfile = "Dockerfile.iso-image"
  target = "iso-image"
  platforms = ["linux/${ARCH}"]
  contexts = {
    base-image = "target:base-image"
    stylus-image = "target:stylus-image"
  }
  depends-on = ["base-image", "stylus-image"]
  args = {
    ARCH = ARCH
    IS_UKI = IS_UKI
    IMAGE_TAG = IMAGE_TAG
  }
  tags = ["palette-installer-image:${IMAGE_TAG}"]
}