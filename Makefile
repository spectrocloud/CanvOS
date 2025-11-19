-include .arg
export

# ==============================================================================
# TARGETS
# ==============================================================================
.PHONY: build build-all-images base-image iso build-provider-images iso-disk-image \
	uki-genkey alpine-all validate-user-data help

.SILENT: uki-genkey validate-user-data

# ==============================================================================
# HELPER VARIABLES
# ==============================================================================
comma := ,
empty :=
space := $(empty) $(empty)

# ==============================================================================
# CONFIGURATION DEFAULTS
# ==============================================================================
PUSH ?= true
DEBUG ?= false
NO_CACHE ?= false

# ==============================================================================
# COMPUTED VARIABLES
# ==============================================================================
# Target type selection based on IS_UKI flag
PROVIDER_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),uki-provider-image,provider-image)
ISO_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),build-uki-iso,build-iso)

# Docker buildx progress output
DOCKER_BUILD_OUT = $(if $(filter true,$(DEBUG)),--progress=plain,)

# Docker buildx no-cache flag
DOCKER_NO_CACHE = $(if $(filter true,$(NO_CACHE)),--no-cache,)

# K8S versions: either from K8S_VERSION (comma-separated) or k8s_version.json
ALL_K8S_VERSIONS = $(if $(strip $(K8S_VERSION)),\
	$(subst $(comma),$(space),$(K8S_VERSION)),\
	$(shell jq -r --arg key "$(K8S_DISTRIBUTION)" 'if .[$$key] then .[$$key][] else empty end' k8s_version.json))

# Common BAKE_ARGS for pushing images
PUSH_ARGS = $(if $(filter true,$(PUSH)),--set *.output=type=image$(comma)push=$(PUSH),)

# ==============================================================================
# CORE BUILD TARGET
# ==============================================================================
build:
	@$(if $(BAKE_ENV),env $(BAKE_ENV)) \
	docker buildx bake ${DOCKER_BUILD_OUT} ${DOCKER_NO_CACHE} ${TARGET} $(BAKE_ARGS)

# ==============================================================================
# MAIN BUILD TARGETS
# ==============================================================================
build-all-images: build-provider-images iso

base-image:
	$(MAKE) TARGET=base-image build

iso:
	$(MAKE) TARGET=$(ISO_TARGET_TYPE) build

iso-disk-image:
	$(MAKE) TARGET=iso-disk-image build BAKE_ARGS="$(PUSH_ARGS)"

# ==============================================================================
# PROVIDER IMAGE BUILD TARGETS
# ==============================================================================
build-provider-images: .check-provider-prereqs $(addprefix .build-provider-image-,$(strip $(ALL_K8S_VERSIONS)))
	@echo "All provider images built successfully"

.build-provider-image-%: .check-provider-prereqs
	@echo "Building provider image for k8s version: $*"
	$(MAKE) TARGET=$(PROVIDER_TARGET_TYPE) \
		BAKE_ENV="K8S_VERSION=$*" \
		BAKE_ARGS="--set *.args.K8S_VERSION=$* $(PUSH_ARGS)" \
		build

.check-provider-prereqs:
	@$(if $(strip $(K8S_DISTRIBUTION)),,\
		$(error K8S_DISTRIBUTION is not set. Please set K8S_DISTRIBUTION to kubeadm, kubeadm-fips, k3s, nodeadm, rke2 or canonical))
	@$(if $(strip $(ALL_K8S_VERSIONS)),,\
		$(error No versions found for K8S_DISTRIBUTION=$(K8S_DISTRIBUTION)))

# ==============================================================================
# UTILITY TARGETS
# ==============================================================================
uki-genkey:
	$(MAKE) TARGET=uki-genkey build
	./keys.sh secure-boot/

validate-user-data:
	$(MAKE) TARGET=validate-user-data build

alpine-all:
	$(MAKE) TARGET=alpine-all BAKE_ARGS="$(PUSH_ARGS)" build

help:
	@echo "Available targets:"
	@echo "  build-all-images      - Build all provider images and ISO"
	@echo "  base-image            - Build base image"
	@echo "  iso                   - Build ISO installer"
	@echo "  iso-disk-image        - Build ISO disk image"
	@echo "  build-provider-images - Build all provider images for configured K8S versions"
	@echo "  uki-genkey            - Generate UKI secure boot keys"
	@echo "  validate-user-data    - Validate user-data configuration"
	@echo ""
	@echo "Configuration (set in .arg file or as make variables):"
	@echo "  PUSH                  - Push images to registry (default: true)"
	@echo "  DEBUG                 - Enable debug output (default: false)"
	@echo "  NO_CACHE              - Disable build cache (default: false)"
