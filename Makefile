-include .arg
export

# ==============================================================================
# TARGETS
# ==============================================================================
.PHONY: build build-all-images iso build-provider-images iso-disk-image \
	uki-genkey secure-boot-dirs alpine-all validate-user-data \
	cloud-image raw-image aws-cloud-image iso-image-cloud cloud-image-tools \
	maas-image iso-image-maas \
	internal-slink iso-efi-size-check \
	clean clean-all clean-cloud-image clean-keys help

.SILENT: uki-genkey validate-user-data clean-cloud-image secure-boot-dirs help cloud-image

# ==============================================================================
# CONSTANTS
# ==============================================================================
AURORABOOT_IMAGE := quay.io/kairos/auroraboot:v0.19.0

# Docker Bake file configuration
COMMON_BAKE_FILE := docker-bake-common.hcl
MAIN_BAKE_FILE := docker-bake.hcl

# Bake file arguments for main builds (includes common + main bake files)
BAKE_FILES := -f $(COMMON_BAKE_FILE) -f $(MAIN_BAKE_FILE)

CLOUD_IMAGE_DIR := $(CURDIR)/build/cloud-image
MAAS_IMAGE_DIR := $(CURDIR)/build/maas-image
ISO_IMAGE_CLOUD := palette-installer-image-cloud:latest
ISO_IMAGE_MAAS := palette-installer-image-maas:latest

CLOUD_IMAGE_TOOLS := us-docker.pkg.dev/palette-images/edge/canvos/cloud-image-tools:latest
MAAS_IMAGE_NAME ?= kairos-ubuntu-maas

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


USER_DATA := $(or $(USER_DATA),user-data)

# Common Configuration expressions for building targets
PUSH_ARGS = $(if $(filter true,$(PUSH)),--set *.output=type=image$(comma)push=$(PUSH),)
DRY_RUN_ARGS = $(if $(filter true,$(DRY_RUN)),--print,)
DOCKER_BUILD_OUT = $(if $(filter true,$(DEBUG)),--progress=plain --debug,)
DOCKER_NO_CACHE = $(if $(filter true,$(NO_CACHE)),--no-cache,)

# ==============================================================================
# COMPUTED VARIABLES
# ==============================================================================
PROVIDER_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),uki-provider-image,provider-image)
ISO_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),build-uki-iso,build-iso)

ALL_K8S_VERSIONS = $(if $(strip $(K8S_VERSION)),\
	$(subst $(comma),$(space),$(K8S_VERSION)),\
	$(shell jq -r --arg key "$(K8S_DISTRIBUTION)" 'if .[$$key] then .[$$key][] else empty end' k8s_version.json))

# Check for content directories, cluster config, and edge config
HAS_CONTENT := $(shell ls -d content-* 2>/dev/null | head -1)
HAS_CLUSTERCONFIG := $(if $(CLUSTERCONFIG),$(shell test -f "$(CLUSTERCONFIG)" && echo yes),)
HAS_EDGE_CONFIG := $(if $(EDGE_CUSTOM_CONFIG),$(shell test -f "$(EDGE_CUSTOM_CONFIG)" && echo yes),)
HAS_USER_DATA := $(shell test -f "$(USER_DATA)" && echo yes)

# ==============================================================================
# CORE BUILD TARGET
# ==============================================================================
build:
	$(if $(BAKE_ENV),env $(BAKE_ENV)) \
	docker buildx bake $(BAKE_FILES) $(DRY_RUN_ARGS) $(DOCKER_BUILD_OUT) $(DOCKER_NO_CACHE) $(TARGET) $(BAKE_ARGS)

# ==============================================================================
# MAIN BUILD TARGETS
# ==============================================================================
build-all-images: build-provider-images iso

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
	@$(MAKE) TARGET=$(PROVIDER_TARGET_TYPE) \
		BAKE_ENV="K8S_VERSION=$*" \
		BAKE_ARGS="--set *.args.K8S_VERSION=$* $(PUSH_ARGS)" \
		build

.check-provider-prereqs:
	@$(if $(strip $(K8S_DISTRIBUTION)),,\
		$(error K8S_DISTRIBUTION is not set. Please set K8S_DISTRIBUTION to kubeadm, kubeadm-fips, k3s, nodeadm, rke2 or canonical))
	@$(if $(strip $(ALL_K8S_VERSIONS)),,\
		$(error No versions found for K8S_DISTRIBUTION=$(K8S_DISTRIBUTION)))


# ------------------------------------------------------------------------------
# Cloud Image
# ------------------------------------------------------------------------------
# Build AWS AMI from cloud image
aws-cloud-image: cloud-image
	@echo "Creating AWS AMI from cloud image"
	$(MAKE) TARGET=aws-cloud-image build BAKE_ARGS="--set *.contexts.raw-image=$(CLOUD_IMAGE_DIR)"

cloud-image: iso-image-cloud cloud-image-tools content-partition-cloud
	$(MAKE) kairos-raw-image OUTPUT_DIR=$(CLOUD_IMAGE_DIR) CONTAINER_IMAGE=$(ISO_IMAGE_CLOUD)
	@ls -lh $(CLOUD_IMAGE_DIR)/* 2>/dev/null || true

iso-image-cloud:
	$(MAKE) TARGET=iso-image-cloud build

content-partition-cloud:
	@if [ -n "$(HAS_CONTENT)" ] || [ -n "$(HAS_CLUSTERCONFIG)" ] || [ -n "$(HAS_EDGE_CONFIG)" ]; then \
		echo "Adding content partition to cloud image"; \
		RAW_FILE=$$(ls $(CLOUD_IMAGE_DIR)/*.raw 2>/dev/null || ls $(CLOUD_IMAGE_DIR)/*.img 2>/dev/null | head -1); \
		if [ -z "$$RAW_FILE" ]; then \
			echo "Error: No raw image found in $(CLOUD_IMAGE_DIR)"; \
			exit 1; \
		fi; \
		echo "Adding content partition to: $$RAW_FILE"; \
		docker run --rm --privileged --net host \
			-v /dev:/dev \
			-v $(CLOUD_IMAGE_DIR):/workdir \
			$(foreach dir,$(wildcard content-*),-v $(CURDIR)/$(dir):/workdir/$(dir):ro) \
			$(if $(HAS_CLUSTERCONFIG),-v $(CURDIR)/$(CLUSTERCONFIG):/workdir/spc.tgz:ro,) \
			$(if $(HAS_EDGE_CONFIG),-v $(CURDIR)/$(EDGE_CUSTOM_CONFIG):/workdir/edge_custom_config.yaml:ro,) \
			-e CLUSTERCONFIG=$(if $(HAS_CLUSTERCONFIG),/workdir/spc.tgz,) \
			-e EDGE_CUSTOM_CONFIG=$(if $(HAS_EDGE_CONFIG),/workdir/edge_custom_config.yaml,) \
			$(CLOUD_IMAGE_TOOLS) \
			-c "/scripts/add-content-partition.sh /workdir/$$(basename $$RAW_FILE)"; \
	else \
		echo "Skipped adding content partition (no content files)"; \
	fi

# ------------------------------------------------------------------------------
# MAAS Image
# ------------------------------------------------------------------------------
maas-image: raw-disk-maas build-maas-composite
	@echo "MAAS image build complete"
	@ls -lh $(MAAS_IMAGE_DIR)/* 2>/dev/null || true

# raw-disk-maas: iso-image-maas cloud-image-tools
raw-disk-maas: 
	@echo "Creating base raw disk image for MAAS"
	$(MAKE) kairos-raw-image OUTPUT_DIR=$(MAAS_IMAGE_DIR) CONTAINER_IMAGE=$(ISO_IMAGE_MAAS)

# Build MAAS composite image (adds Ubuntu rootfs + content partition)
build-maas-composite: cloud-image-tools
	@RAW_FILE=$$(ls $(MAAS_IMAGE_DIR)/*.raw 2>/dev/null || ls $(MAAS_IMAGE_DIR)/*.img 2>/dev/null | head -1); \
	if [ -z "$$RAW_FILE" ]; then \
		echo "Error: No raw image found in $(MAAS_IMAGE_DIR)"; \
		exit 1; \
	fi; \
	echo "Building MAAS composite from: $$RAW_FILE"; \
	docker run --rm --privileged --net host \
		-v /dev:/dev \
		-v $(MAAS_IMAGE_DIR):/workdir \
		$(foreach dir,$(wildcard content-*),-v $(CURDIR)/$(dir):/input/$(dir):ro) \
		$(if $(HAS_CLUSTERCONFIG),-v $(CURDIR)/$(CLUSTERCONFIG):/input/spc.tgz:ro,) \
		$(if $(HAS_EDGE_CONFIG),-v $(CURDIR)/$(EDGE_CUSTOM_CONFIG):/input/edge_custom_config.yaml:ro,) \
		-e CURTIN_HOOKS_SCRIPT=/scripts/curtin-hooks \
		-e CONTENT_BASE_DIR=/input \
		-e CLUSTERCONFIG=$(if $(HAS_CLUSTERCONFIG),/input/spc.tgz,) \
		-e EDGE_CUSTOM_CONFIG=$(if $(HAS_EDGE_CONFIG),/input/edge_custom_config.yaml,) \
		-e MAAS_IMAGE_NAME=$(MAAS_IMAGE_NAME) \
		$(CLOUD_IMAGE_TOOLS) \
		-c "/scripts/build-kairos-maas.sh /workdir/$$(basename $$RAW_FILE) $(MAAS_IMAGE_NAME)"

iso-image-maas:
	$(MAKE) TARGET=iso-image-maas build

# ==============================================================================
# INTERNAL TARGETs (for MAAS and Cloud images)
# ==============================================================================
kairos-raw-image: validate-user-data
	@mkdir -p $(OUTPUT_DIR)
	docker run --rm --net host --privileged \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(OUTPUT_DIR):/output \
		$(if $(HAS_USER_DATA),-v $(CURDIR)/$(USER_DATA):/config.yaml:ro,) \
		$(AURORABOOT_IMAGE) \
		$(if $(filter true,$(DEBUG)),--debug,) \
		--set "disable_http_server=true" \
		--set "disable_netboot=true" \
		--set "disk.efi=true" \
		--set "arch=$(ARCH)" \
		--set "container_image=$(CONTAINER_IMAGE)" \
		--set "state_dir=/output" \
		$(if $(HAS_USER_DATA),--cloud-config /config.yaml,--set "no_default_cloud_config=true")

# ==============================================================================
# UTILITY TARGETS
# ==============================================================================
uki-genkey:
	$(MAKE) TARGET=uki-genkey build
	./keys.sh secure-boot/

secure-boot-dirs:
	mkdir -p secure-boot/enrollment secure-boot/exported-keys secure-boot/private-keys secure-boot/public-keys
	find secure-boot -type d -exec chmod 0700 {} \;
	find secure-boot -type f -exec chmod 0600 {} \;
	echo "Created secure-boot directory structure"

validate-user-data:
	$(MAKE) TARGET=validate-user-data build

internal-slink:
	$(MAKE) TARGET=internal-slink build

iso-efi-size-check:
	$(MAKE) TARGET=iso-efi-size-check build

alpine-all:
	$(MAKE) TARGET=alpine-all BAKE_ARGS="$(PUSH_ARGS)" build

cloud-image-tools:
	$(MAKE) TARGET=cloud-image-tools BAKE_ARGS="$(PUSH_ARGS)" build

# ==============================================================================
# CLEAN TARGETS
# ==============================================================================
clean-all: clean clean-keys

clean:
	rm -rf build

clean-cloud-image:
	rm -rf $(CLOUD_IMAGE_DIR) $(MAAS_IMAGE_DIR)

clean-keys:
	rm -rf secure-boot

# ==============================================================================
# Colors for help output
BOLD   := $(shell printf '\033[1m')
CYAN   := $(shell printf '\033[36m')
GREEN  := $(shell printf '\033[32m')
YELLOW := $(shell printf '\033[33m')
RESET  := $(shell printf '\033[0m')

help:
	@echo ""
	@echo "$(BOLD)CanvOS Build System$(RESET)"
	@echo ""
	@echo "$(CYAN)Build Targets:$(RESET)"
	@echo "  $(GREEN)build-all-images$(RESET)      Build all provider images and ISO"
	@echo "  $(GREEN)iso$(RESET)                   Build ISO installer"
	@echo "  $(GREEN)iso-disk-image$(RESET)        Build ISO disk image and push to registry"
	@echo "  $(GREEN)build-provider-images$(RESET) Build provider images for configured K8S versions"
	@echo ""
	@echo "$(CYAN)Cloud Image Targets:$(RESET) $(YELLOW)(require privileged Docker)$(RESET)"
	@echo "  $(GREEN)cloud-image$(RESET)           Build raw cloud disk image with content partition"
	@echo "  $(GREEN)aws-cloud-image$(RESET)       Build AWS AMI from cloud image"
	@echo "  $(GREEN)raw-image$(RESET)             Alias for cloud-image"
	@echo ""
	@echo "$(CYAN)MAAS Image Targets:$(RESET) $(YELLOW)(require privileged Docker)$(RESET)"
	@echo "  $(GREEN)maas-image$(RESET)            Build MAAS raw disk image with content partition"
	@echo ""
	@echo "$(CYAN)Utility Targets:$(RESET)"
	@echo "  $(GREEN)uki-genkey$(RESET)            Generate UKI secure boot keys"
	@echo "  $(GREEN)secure-boot-dirs$(RESET)      Create secure-boot directory structure"
	@echo "  $(GREEN)validate-user-data$(RESET)    Validate user-data configuration"
	@echo ""
	@echo "$(CYAN)Clean Targets:$(RESET)"
	@echo "  $(GREEN)clean$(RESET)                 Remove build directory"
	@echo "  $(GREEN)clean-all$(RESET)             Remove build directory and secure boot keys"
	@echo "  $(GREEN)clean-cloud-image$(RESET)     Remove cloud/MAAS image artifacts"
	@echo "  $(GREEN)clean-keys$(RESET)            Remove secure boot keys"
	@echo ""
	@echo "$(CYAN)Configuration:$(RESET) (set in .arg file or as make variables)"
	@echo "  PUSH=true|false           Push images to registry (default: true)"
	@echo "  DEBUG=true|false          Enable debug output (default: false)"
	@echo "  NO_CACHE=true|false       Disable build cache (default: false)"
	@echo "  DRY_RUN=true|false        Print commands without executing"
	@echo ""
	@echo "$(CYAN)Cloud/MAAS Configuration:$(RESET)"
	@echo "  USER_DATA=<path>          Cloud config file (default: user-data)"
	@echo "  CLUSTERCONFIG=<path>      Cluster config archive (spc.tgz)"
	@echo "  EDGE_CUSTOM_CONFIG=<path> Edge custom config yaml"
	@echo "  content-*/                Content bundle directories (auto-detected)"
	@echo ""
	@echo "$(YELLOW)For base image builds:$(RESET) make -f Makefile.base-images help"
	@echo ""