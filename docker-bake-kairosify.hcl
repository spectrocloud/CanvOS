# kairos-init is tagged with the kairos release version, so KAIROS_VERSION is
# the single knob and the kairos-init image ref is derived from it below instead
# of being pinned a second time. The derivation is evaluated from this variable,
# so move it via the environment (or set KAIROS_INIT_IMAGE directly), not via
# --set kairosify.args.KAIROS_VERSION, which would not move the image ref.
variable "KAIROS_VERSION" {
  default = "v4.3.0"
}

variable "KAIROS_INIT_IMAGE" {
    default = "quay.io/kairos/kairos-init:${KAIROS_VERSION}"
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