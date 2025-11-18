-include .arg
export

.PHONY: base-image build-iso build-provider-images iso-disk-image

# Helper variables for Make-based processing
comma := ,
empty :=
space := $(empty) $(empty)

# Get target type based on IS_UKI
PROVIDER_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),uki-provider-image,provider-image)
ISO_TARGET_TYPE = $(if $(filter true,$(IS_UKI)),build-uki-iso,build-iso)

# Get versions: either from K8S_VERSION or k8s_version.json
ALL_K8S_VERSIONS = $(if $(strip $(K8S_VERSION)),\
	$(subst $(comma),$(space),$(K8S_VERSION)),\
	$(shell jq -r --arg key "$(K8S_DISTRIBUTION)" 'if .[$$key] then .[$$key][] else empty end' k8s_version.json))

PUSH ?= true
IS_UKI ?= false

build-all-images: build-provider-images iso


build:
	docker buildx bake ${TARGET}

base-image:
	# docker buildx bake base-image 
	$(MAKE) TARGET=base-image build

iso:
	# docker buildx bake $(ISO_TARGET_TYPE)
	$(MAKE) TARGET=$(ISO_TARGET_TYPE) build

iso-disk-image:
	# docker buildx bake iso-disk-image
	$(MAKE) TARGET=iso-disk-image build

build-provider-images: check-k8s-distribution check-versions $(addprefix build-provider-image-,$(strip $(ALL_K8S_VERSIONS)))
	@echo "All provider images built successfully"

build-provider-image-%: check-k8s-distribution
	@echo "building for k8s version - $*"
	@env K8S_VERSION=$* docker buildx bake $(PROVIDER_TARGET_TYPE) --set *.args.K8S_VERSION=$*
	# $(MAKE) TARGET=$(PROVIDER_TARGET_TYPE) build K8S_VERSION=$*

check-versions:
	@$(if $(strip $(ALL_K8S_VERSIONS)),,$(error No versions found for K8S_DISTRIBUTION=$(K8S_DISTRIBUTION)))

check-k8s-distribution:
	@$(if $(strip $(K8S_DISTRIBUTION)),,$(error K8S_DISTRIBUTION is not set. Please set K8S_DISTRIBUTION to kubeadm, kubeadm-fips, k3s, nodeadm, rke2 or canonical))

uki-genkey:
	# docker buildx bake uki-genkey
	$(MAKE) TARGET=uki-genkey build
