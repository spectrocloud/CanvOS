variable "KAIROS_INIT_IMAGE" {
    default = "quay.io/kairos/kairos-init:v0.5.20"
}

variable "ARCH" {
    default = "amd64"
}

variable "BASE_OS_IMAGE" {
    default = "ubuntu:20.04"
}

variable "MODEL" {
    default = "generic"
}

variable "KAIROS_VERSION" {
  default = "v3.5.3"
}

variable "TRUSTED_BOOT" {
    type = bool
    default = false
}

variable "TAG" {
    default = "kairosify:latest"
}

target "kairosify" {
  dockerfile = "dockerfiles/kairosify/Dockerfile.kairosify"
  platforms = ["linux/${ARCH}"]
  args = {
    BASE_OS_IMAGE = BASE_OS_IMAGE
    KAIROS_INIT_IMAGE = KAIROS_INIT_IMAGE
    KAIROS_VERSION = KAIROS_VERSION
    TRUSTED_BOOT = TRUSTED_BOOT
    MODEL = MODEL
  }
  tags = [TAG]
}