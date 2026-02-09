# =============================================================================
# Docker Bake Common Variables
# =============================================================================
# This file contains shared variables used across all docker-bake configurations.
# Include this file with your specific bake file using multiple -f flags:
#
# Usage:
#   docker buildx bake -f docker-bake-common.hcl -f docker-bake.hcl <target>
#   docker buildx bake -f docker-bake-common.hcl -f docker-bake-base-images.hcl <target>
#
# Variables defined in later files (-f order) will override earlier ones.
# =============================================================================

# -----------------------------------------------------------------------------
# Core Version Variables
# -----------------------------------------------------------------------------

variable "KAIROS_VERSION" {
  default     = "v3.5.9"
  description = "Kairos framework version"
}

variable "KAIROS_INIT_IMAGE" {
  default     = "quay.io/kairos/kairos-init:v0.5.28"
  description = "Kairos init image for kairosification"
}

# -----------------------------------------------------------------------------
# Architecture and Platform
# -----------------------------------------------------------------------------

variable "ARCH" {
  default     = "amd64"
  description = "Target architecture (amd64, arm64)"
}

# -----------------------------------------------------------------------------
# Image Registry and Tagging
# -----------------------------------------------------------------------------

variable "IMAGE_REGISTRY" {
  default     = ""
  description = "Container registry to push images (e.g., ghcr.io/myorg, us-docker.pkg.dev/project)"
}

variable "IMAGE_TAG" {
  default     = "latest"
  description = "Tag for built images (can be overridden by specific bake files)"
}

variable "PUSH_IMAGES" {
  type        = bool
  default     = false
  description = "Whether to push images to registry"
}

# -----------------------------------------------------------------------------
# FIPS Configuration
# -----------------------------------------------------------------------------

variable "FIPS_ENABLED" {
  type        = bool
  default     = false
  description = "Enable FIPS-compliant builds"
}
