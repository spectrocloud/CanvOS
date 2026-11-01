# Build all Kairos base images from one definition.
#
# Run from this directory (bake resolves context/dockerfile/secret paths
# relative to the process cwd):
#
#   cd base-images
#   docker buildx bake --allow=fs.read=.. --print public-distro
#   docker buildx bake --allow=fs.read=.. public-distro --push
#   docker buildx bake --allow=fs.read=.. -f docker-bake.hcl -f hadron/modules.json public --push
#
# hadron/modules.json holds the Hadron release -> kernel module map and is only
# needed for Hadron targets (groups public-hadron and public); or set it once with
#   export BUILDX_BAKE_FILE=docker-bake.hcl:hadron/modules.json
#
# `--allow=fs.read=..` is required because the shared distrust script still
# lives in ../scripts. If it is ever moved under base-images/, the flag can go.
#
# Secret tiers are groups:
#   public         no credentials: public-distro + public-hadron
#   public-distro  upstream-distro bases (kairosify, Ubuntu UKI)
#   public-hadron  Hadron variants + modules image (needs hadron/modules.json)
#   rhsm        RHSM username/password            (rhel-fips, rhel-core, rhel-stig)
#   satellite   Satellite activation key          (rhel-core *-satellite)
#   pro         Ubuntu Pro attach config          (ubuntu-fips)
#   scc         SUSE registration code            (slem 5.5)
#
# Secrets are BuildKit secrets, never build args. BuildKit mounts the value at
# /run/secrets/<id> for the consuming RUN only; nothing is written to an image
# layer and there is nothing to clean up on success or failure.
#
# All secrets are supplied by the caller's environment, except the Ubuntu Pro
# attach config, which is a file (see UBUNTU_PRO_CONFIG below).
#
# Secret environment variables consumed by targets:
#   RHSM_USERNAME, RHSM_PASSWORD          rhsm tier
#   SATELLITE_ACTIVATION_KEY              satellite tier (+ SAT_ORG, SAT_HOST)
#   UBUNTU_PRO_CONFIG                     pro tier (file path, see below)
#   SUSE_REGCODE                          scc tier
#
# Layout: variables, functions, image targets (public, Ubuntu UKI, Ubuntu FIPS,
# RHEL, SLE Micro, Hadron), internal "_" base targets, groups.

# ===========================================================================
# Variables
# ===========================================================================

# Dev registry by default. Production (palette-images, palette-images-fips) is
# only reached by a manual retag/promotion, so Ubuntu Pro FIPS images, which
# must never be published, cannot be pushed there by accident.
variable "REGISTRY" { default = "us-east1-docker.pkg.dev/spectro-images/edge/base" }
variable "ARCH"     { default = "amd64" }
variable "MODEL"    { default = "generic" }

# Kairos release. It is passed to kairos-init --version, is the tag of the
# kairos-init image, and is the version component of every base image tag.
variable "KAIROS_VERSION" { default = "v4.4.0" }

# kairos-init is published with the same tag as the Kairos release it installs.
# Override only to use a mirror (e.g. an air-gapped registry); keep the tag
# equal to KAIROS_VERSION.
variable "KAIROS_INIT_IMAGE" { default = "quay.io/kairos/kairos-init:${KAIROS_VERSION}" }

# kairosify-custom: any upstream OS image to kairosify (not part of a group).
#   BASE_OS_IMAGE=rockylinux:9 docker buildx bake --allow=fs.read=.. kairosify-custom
variable "BASE_OS_IMAGE" { default = "" }


# Path (not contents) of the Ubuntu Pro attach config for ubuntu-fips, relative
# to this directory. Defaults to ubuntu-fips/pro-attach-config.yaml, a git-ignored
# copy of ubuntu-fips/pro-attach-config.yaml.template; CI points
# it at a file rendered from Vault outside the checkout (add
# --allow=fs.read=<that dir>). The file reaches the build only as the BuildKit
# secret `pro-attach-config`; ubuntu-fips/.dockerignore keeps it out of the
# build context. Never turn the token itself into a bake variable or arg:
# variables and args are recorded in provenance and build history.
variable "UBUNTU_PRO_CONFIG" { default = "ubuntu-fips/pro-attach-config.yaml" }

# Ubuntu UKI: keep the AMD/NVIDIA GPU firmware that is trimmed by default to
# stay under the ~1 GiB UEFI initrd limit.
variable "KEEP_GPU_FIRMWARE" {
  type    = bool
  default = false
}

# ubuntu-fips STIG switches.
variable "ENABLE_STIG" {
  type    = bool
  default = true
}

variable "SKIP_STIG_BANNER" {
  type    = bool
  default = true
}

# RHEL Satellite (non-secret; the activation key is a secret).
variable "SAT_ORG"  { default = "" }
variable "SAT_HOST" { default = "" }

# Upstream Hadron release; must have an entry in hadron/modules.json.
variable "HADRON_VERSION" { default = "v0.5.3" }

# Hadron release -> kernel modules, loaded from hadron/modules.json (pass it with
# -f). Empty here so non-Hadron targets still resolve when the file is omitted.
variable "HADRON_RELEASES" { default = [] }

# ===========================================================================
# Functions
# ===========================================================================

# Standard Kairos base tag:
#   <registry>/<repo>:<os_version>-core-<arch>-<model>-<kairos version><suffix>
# <REGISTRY>/<repo>:<os_version>-core-<ARCH>-<MODEL>-<KAIROS_VERSION><suffix>
# The prefix is the upstream Kairos format. Modifiers go in suffix, in this
# order: -fips (baseline), -stig (hardening), -uki (boot), -sat (build method).
function "kairos_tag" {
  params = [repo, os_version, suffix]
  result = "${REGISTRY}/${repo}:${os_version}-core-${ARCH}-${MODEL}-${KAIROS_VERSION}${suffix}"
}

# Booleans -> the string form each Dockerfile compares against. The conditional
# forces a real bool, so a quoted "1" or "True" in an override file is
# normalised (or rejected) here instead of reaching the Dockerfile as-is.
#   bool_flag: "1"/"0"        (ubuntu-fips ENABLE_STIG, SKIP_STIG_BANNER)
#   bool_str:  "true"/"false" (ubuntu-uki KEEP_GPU_FIRMWARE)
function "bool_flag" {
  params = [value]
  result = value ? "1" : "0"
}

function "bool_str" {
  params = [value]
  result = value ? "true" : "false"
}

# Tag-safe name for an arbitrary image ref: last path element, ':' and '@' -> '-'.
#   registry.example.com/team/rocky:9 -> rocky-9
function "image_name" {
  params = [image]
  result = replace(replace(element(split("/", image), length(split("/", image)) - 1), "@", "-"), ":", "-")
}

# Spectro Hadron modules image. Per arch, like every other image: one tag per
# architecture, so amd64 and arm64 builds never overwrite each other.
function "hadron_modules_image" {
  params = []
  result = "${REGISTRY}/hadron-modules:${HADRON_VERSION}-${ARCH}"
}

# Digest-pinned image of a kernel module layer for HADRON_VERSION, from
# HADRON_RELEASES: ghcr.io/kairos-io/hadron-layers/<name>@<digest>.
# A release or module missing from hadron/modules.json (or the file not passed)
# yields an invalid ref naming what is missing, so only Hadron builds fail.
function "hadron_module" {
  params = [name]
  result = try(
    "ghcr.io/kairos-io/hadron-layers/${name}@${[for m in [for r in HADRON_RELEASES : r if r.version == HADRON_VERSION][0].modules : m if m.name == name][0].digest}",
    "MISSING:${name}-for-hadron-${HADRON_VERSION}-not-in-hadron/modules.json"
  )
}

# ===========================================================================
# Public: credential-free Kairos bases from upstream distro images
# ===========================================================================

# kairosify-ubuntu-22-04, kairosify-ubuntu-24-04, kairosify-opensuse-16-0
target "kairosify" {
  name     = "kairosify-${os.name}"
  inherits = ["_kairosify"]
  matrix = {
    os = [
      { name = "ubuntu-22-04",  image = "ubuntu:22.04",       repo = "kairos-ubuntu",   version = "22.04" },
      { name = "ubuntu-24-04",  image = "ubuntu:24.04",       repo = "kairos-ubuntu",   version = "24.04" },
      { name = "opensuse-16-0", image = "opensuse/leap:16.0", repo = "kairos-opensuse", version = "leap-16.0" },
    ]
  }
  args = { BASE_OS_IMAGE = os.image }
  tags = [kairos_tag(os.repo, os.version, "")]
}

# Any upstream image: BASE_OS_IMAGE=<image> docker buildx bake kairosify-custom
target "kairosify-custom" {
  inherits = ["_kairosify"]
  args     = { BASE_OS_IMAGE = BASE_OS_IMAGE }
  tags     = [kairos_tag("kairos-custom", image_name(BASE_OS_IMAGE), "")]
}

# ===========================================================================
# Ubuntu trusted boot (UKI)
# ===========================================================================

# AMD/NVIDIA GPU firmware is trimmed unless KEEP_GPU_FIRMWARE=true.
target "ubuntu-uki-24-04" {
  inherits = ["_kairos"]
  context  = "./ubuntu-uki/24.04"
  args = {
    VERSION           = KAIROS_VERSION
    KEEP_GPU_FIRMWARE = bool_str(KEEP_GPU_FIRMWARE)
  }
  tags = [kairos_tag("kairos-ubuntu", "24.04", "-uki")]
}

# ===========================================================================
# Ubuntu FIPS (+ STIG)
# ===========================================================================

# ubuntu-fips-22-04, ubuntu-fips-24-04
target "ubuntu-fips" {
  name       = "ubuntu-fips-${replace(ver, ".", "-")}"
  matrix     = { ver = ["22.04", "24.04"] }
  inherits   = ["_kairos"]
  context    = "./ubuntu-fips"
  dockerfile = "${ver}/Dockerfile.ubuntu${ver}-fips"
  args = {
    VERSION          = KAIROS_VERSION
    ENABLE_STIG      = bool_flag(ENABLE_STIG)
    SKIP_STIG_BANNER = bool_flag(SKIP_STIG_BANNER)
  }
  secret = ["id=pro-attach-config,src=${UBUNTU_PRO_CONFIG}"]
  tags   = [kairos_tag("kairos-ubuntu", ver, ENABLE_STIG ? "-fips-stig" : "-fips")]
}

# ===========================================================================
# RHEL: core, FIPS, STIG (direct RHSM) and Satellite
# ===========================================================================

# rhel-core-9, rhel-core-10, rhel-fips-9, rhel-fips-10
target "rhel" {
  name       = "rhel-${flavor}-${ver}"
  matrix     = { flavor = ["core", "fips"], ver = ["9", "10"] }
  inherits   = ["_kairos", "_rhsm"]
  context    = flavor == "core" ? "./rhel-core-images" : "./rhel-fips"
  dockerfile = "Dockerfile.rhel${ver}"
  tags       = [kairos_tag("kairos-rhel", ver, flavor == "fips" ? "-fips" : "")]
}

# rhel-stig-9, rhel-stig-9-fips
target "rhel-stig" {
  name       = "rhel-stig-9${fips}"
  matrix     = { fips = ["", "-fips"] }
  inherits   = ["_kairos", "_rhsm"]
  context    = "./rhel-stig"
  dockerfile = "Dockerfile.rhel9${fips}"
  tags       = [kairos_tag("kairos-rhel", "9", "${fips}-stig")]
}

# rhel-core-9-satellite, rhel-core-10-satellite
target "rhel-satellite" {
  name       = "rhel-core-${ver}-satellite"
  matrix     = { ver = ["9", "10"] }
  inherits   = ["_kairos"]
  context    = "./rhel-core-images"
  dockerfile = "Dockerfile.rhel${ver}.sat"
  args = {
    ORGNAME     = SAT_ORG
    SATHOSTNAME = SAT_HOST
  }
  secret = ["id=KEYNAME,env=SATELLITE_ACTIVATION_KEY"]
  tags   = [kairos_tag("kairos-rhel", ver, "-sat")]
}


# ===========================================================================
# SLE Micro
# ===========================================================================

# Registers a fresh SCC system per build and deregisters it at the end;
# SCC_NONCE (build timestamp) keeps a cached registration from being reused.
target "slem-5-5" {
  inherits = ["_kairos"]
  context  = "./slem/5.5"
  args = {
    TRUSTED_BOOT = "false"
    SCC_NONCE    = timestamp()
  }
  secret   = ["id=SUSE_REGCODE,env=SUSE_REGCODE"]
  tags     = [kairos_tag("kairos-slem", "5.5", "")]
}

# ===========================================================================
# Hadron: vendor base + modules layer
# ===========================================================================

# Spectro modules layer (DRBD, rsyslog, logrotate, iproute2, guest agents).
# DRBD comes from hadron/modules.json for HADRON_VERSION, so it matches the kernel.
target "hadron-modules" {
  context    = "./hadron"
  dockerfile = "Dockerfile.modules"
  args = {
    HADRON_VERSION = HADRON_VERSION
    DRBD_LAYER     = hadron_module("drbd")
  }
  tags      = [hadron_modules_image()]
  platforms = ["linux/${ARCH}"]
}

# hadron-std, hadron-fips, hadron-uki, hadron-fips-uki.
# FIPS + UKI needs HADRON_VERSION >= v0.5.3 (first hadron-fips-trusted release).
#
# The `contexts` entry keyed by the modules image ref makes the Dockerfile's
# `FROM ${MODULES_IMAGE}` resolve to the hadron-modules target built in the same
# bake run, instead of whatever is (or isn't) in the registry. A standalone
# `docker build` without that context still pulls MODULES_IMAGE.
target "hadron" {
  name       = "hadron-${v.name}"
  matrix = {
    v = [
      { name = "std",      fips = false, uki = false },
      { name = "fips",     fips = true,  uki = false },
      { name = "uki",      fips = false, uki = true  },
      { name = "fips-uki", fips = true,  uki = true  },
    ]
  }
  inherits   = ["_kairos"]
  context    = "./hadron"
  contexts   = { (hadron_modules_image()) = "target:hadron-modules" }
  args = {
    HADRON_VERSION = HADRON_VERSION
    MODULES_IMAGE  = hadron_modules_image()
    FIPS           = bool_str(v.fips)
    IS_UKI         = bool_str(v.uki)
  }
  tags = [kairos_tag("kairos-hadron", HADRON_VERSION, "${v.fips ? "-fips" : ""}${v.uki ? "-uki" : ""}")]
}



# ===========================================================================
# Internal base targets (underscore = abstract, never built directly)
# ===========================================================================

# Everything that runs kairos-init and the eMudhra distrust script.
# MODEL is passed to kairos-init `-m` and appears in the kairos_tag() tags.
target "_kairos" {
  contexts = { scripts = "../scripts" }
  args = {
    KAIROS_VERSION    = KAIROS_VERSION
    KAIROS_INIT_IMAGE = KAIROS_INIT_IMAGE
    MODEL             = MODEL
  }
  platforms = ["linux/${ARCH}"]
}

# Dockerfile.kairosify runs kairos-init on BASE_OS_IMAGE.
target "_kairosify" {
  inherits   = ["_kairos"]
  context    = "."
  dockerfile = "Dockerfile.kairosify"
  args = {
    TRUSTED_BOOT = "false"
  }
}

target "_rhsm" {
  secret = [
    "id=RHSM_USERNAME,env=RHSM_USERNAME",
    "id=RHSM_PASSWORD,env=RHSM_PASSWORD",
  ]
}

# ===========================================================================
# Groups (credential tiers)
# ===========================================================================

# Credential-free tier: public-distro + public-hadron. Needs -f hadron/modules.json.
group "public" {
  targets = ["public-distro", "public-hadron"]
}

# Upstream-distro bases; needs only docker-bake.hcl.
group "public-distro" {
  targets = [
    "kairosify",
    "ubuntu-uki-24-04",
  ]
}

# Hadron variants plus the modules image (so it is pushed too).
# Needs -f hadron/modules.json.
group "public-hadron" {
  targets = ["hadron", "hadron-modules"]
}

group "rhsm" {
  targets = ["rhel", "rhel-stig"]
}

group "satellite" {
  targets = ["rhel-satellite"]
}

group "pro" {
  targets = ["ubuntu-fips"]
}

group "scc" {
  targets = ["slem-5-5"]
}

# A bare `docker buildx bake` works without hadron/modules.json.
group "default" {
  targets = ["public-distro"]
}
