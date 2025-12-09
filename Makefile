-include .arg
export

# ==============================================================================
# TARGETS
# ==============================================================================
.PHONY: build build-all-images iso build-provider-images iso-disk-image \
	uki-genkey alpine-all validate-user-data raw-image aws-cloud-image \
	iso-image-cloud internal-slink iso-efi-size-check \
	clean clean-all clean-raw-image clean-keys help

.SILENT: uki-genkey validate-user-data clean-raw-image

# ==============================================================================
# CONSTANTS
# ==============================================================================
AURORABOOT_IMAGE := quay.io/kairos/auroraboot:v0.14.0
RAW_IMAGE_DIR := $(CURDIR)/build/raw-image
ISO_IMAGE_CLOUD := palette-installer-image-cloud:latest
ISO_IMAGE_MAAS := palette-installer-image-maas:latest


# ==============================================================================
# HELPER VARIABLES
# ==============================================================================
comma := ,
empty :=
space := $(empty) $(empty)

# ==============================================================================
# CONFIGURATION DEFAULTS
# ==============================================================================
PUSH := $(or $(PUSH),true)
DEBUG := $(or $(DEBUG),false)
NO_CACHE := $(or $(NO_CACHE),false)
DRY_RUN := $(or $(DRY_RUN),false)
ARCH := $(or $(ARCH),amd64)

# Common Configuration expressions for building targets
PUSH_ARGS = $(if $(filter true,$(PUSH)),--set *.output=type=image$(comma)push=$(PUSH),)
# Dry run flag
DRY_RUN_ARGS = $(if $(filter true,$(DRY_RUN)),--print,)
# Progress output flag
DOCKER_BUILD_OUT = $(if $(filter true,$(DEBUG)),--progress=plain,)
# No cache flag
DOCKER_NO_CACHE = $(if $(filter true,$(NO_CACHE)),--no-cache,)

# ==============================================================================
# COMPUTED VARIABLES
# ==============================================================================
# Target type selection based on IS_UKI flag
PROVIDER_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),uki-provider-image,provider-image)
ISO_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),build-uki-iso,build-iso)



# K8S versions: either from K8S_VERSION (comma-separated) or k8s_version.json
ALL_K8S_VERSIONS = $(if $(strip $(K8S_VERSION)),\
	$(subst $(comma),$(space),$(K8S_VERSION)),\
	$(shell jq -r --arg key "$(K8S_DISTRIBUTION)" 'if .[$$key] then .[$$key][] else empty end' k8s_version.json))


# ==============================================================================
# CORE BUILD TARGET
# ==============================================================================
build:
	$(if $(BAKE_ENV),env $(BAKE_ENV)) \
	docker buildx bake $(DRY_RUN_ARGS) $(DOCKER_BUILD_OUT) $(DOCKER_NO_CACHE) $(TARGET) $(BAKE_ARGS)

# ==============================================================================
# MAIN BUILD TARGETS
# ==============================================================================
build-all-images: build-provider-images iso

iso:
	$(MAKE) TARGET=$(ISO_TARGET_TYPE) build

iso-disk-image:
	$(MAKE) TARGET=iso-disk-image build BAKE_ARGS="$(PUSH_ARGS)"

aws-cloud-image: raw-image
	$(MAKE) TARGET=aws-cloud-image build

raw-image: clean-raw-image iso-image-cloud
	mkdir -p $(RAW_IMAGE_DIR)
	docker run --net host --privileged -v /var/run/docker.sock:/var/run/docker.sock \
  	-v $(RAW_IMAGE_DIR):/build \
	-v $(CURDIR)/cloud-images/config/user-data.yaml:/config.yaml \
	--rm -it $(AURORABOOT_IMAGE) \
  	--debug \
  	--set "disable_http_server=true" \
  	--set "disable_netboot=true" \
  	--set "disk.efi=true" \
  	--set "arch=$(ARCH)" \
  	--set "container_image=$(ISO_IMAGE_CLOUD)" \
  	--set "state_dir=/build" \
  	--cloud-config /config.yaml

iso-image-cloud:
	$(MAKE) TARGET=iso-image-cloud build BAKE_ARGS="--set *.tags.ISO_IMAGE_CLOUD=$(ISO_IMAGE_CLOUD)"

# ==============================================================================
# PROVIDER IMAGE BUILD TARGETS
# ==============================================================================
build-provider-images: .check-provider-prereqs $(addprefix .build-provider-image-,$(strip $(ALL_K8S_VERSIONS)))
	@echo "All provider images built successfully"

# PROVIDER IMAGE BUILD TARGETS (INTERNAL)
# ==============================================================================

.build-provider-image-%: .check-provider-prereqs
	@echo "Building provider image for k8s version: $*"
	@$(MAKE) TARGET=$(PROVIDER_TARGET_TYPE) \
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

internal-slink:
	$(MAKE) TARGET=internal-slink build

iso-efi-size-check:
	$(MAKE) TARGET=iso-efi-size-check build

alpine-all:
	$(MAKE) TARGET=alpine-all BAKE_ARGS="$(PUSH_ARGS)" build

# ==============================================================================
# CLEAN TARGETS
# ==============================================================================
clean-all: clean clean-keys

clean:
	rm -rf build

clean-raw-image:
	rm -rf build/raw-image

clean-keys:
	rm -rf secure-boot

# ==============================================================================
help:
	@echo "Available targets:"
	@echo "  build-all-images      - Build all provider images and ISO"
	@echo "  iso                   - Build ISO installer"
	@echo "  iso-disk-image        - Build ISO disk image"
	@echo "  build-provider-images - Build all provider images for configured K8S versions"
	@echo "  raw-image             - Build raw cloud disk image(Requires root privileges)"
	@echo "  aws-cloud-image       - Build AWS AMI from raw image(Requires root privileges)"
	@echo "  uki-genkey            - Generate UKI secure boot keys"
	@echo "  validate-user-data    - Validate user-data configuration"
	@echo "  clean-all             - Remove the build directory and secure boot keys"
	@echo "  clean                 - Remove the build directory"
	@echo "  clean-raw-image       - Remove the $(RAW_IMAGE_DIR) build directory"
	@echo "  clean-keys            - Clean secure boot keys"
	@echo ""
	@echo "Build specific configuration (set in .arg file or as make variables):"
	@echo "  PUSH                  - Push images to registry (default: true)"
	@echo "  DEBUG                 - Enable debug output (default: false)"
	@echo "  NO_CACHE              - Disable build cache (default: false)"
	@echo "  DRY_RUN               - Print build commands without executing (default: false)"
