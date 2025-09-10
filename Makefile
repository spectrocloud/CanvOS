-include .arg
export

.PHONY: base-image build-iso build-provider-images iso-disk-image

PUSH ?= true
IS_UKI ?= false

build-all-images:
	$(MAKE) build-provider-images
	@if [ "$(ARCH)" = "arm64" ]; then \
		docker buildx bake iso-image --set iso-image.platforms=linux/arm64; \
	elif [ "$(ARCH)" = "amd64" ]; then \
		docker buildx bake iso-image --set iso-image.platforms=linux/amd64; \
	fi
	$(MAKE) build-iso

base-image:
	docker buildx bake base-image 

iso:
	@if [ "$(IS_UKI)" = "true" ]; then \
        docker buildx bake build-uki-iso; \
    else \
        docker buildx bake build-iso; \
    fi

iso-disk-image:
	./earthly.sh --push +iso-disk-image


build-provider-images:
	@if [ -z "$(K8S_DISTRIBUTION)" ]; then \
		echo "K8S_DISTRIBUTION is not set. Please set K8S_DISTRIBUTION to kubeadm, kubeadm-fips, k3s, nodeadm, rke2 or canonical." && exit 1; \
	fi
	@if [ "$(IS_UKI)" = "true" ]; then \
		TARGET=uki-provider-image; \
	else \
		TARGET=provider-image; \
	fi; \
	if [ -z "$(K8S_VERSION)" ]; then \
		VERSIONS=$$(jq -r --arg key "$(K8S_DISTRIBUTION)" 'if .[$key] then .[$key][] else empty end' k8s_version.json); \
		if [ -z "$$VERSIONS" ]; then \
			echo "No versions found for K8S_DISTRIBUTION=$(K8S_DISTRIBUTION) in k8s_version.json"; \
			exit 1; \
		fi; \
		for version in $$VERSIONS; do \
			docker buildx bake $$TARGET \
				--set *.args.K8S_VERSION=$$version; \
		done; \
	else \
		docker buildx bake $$TARGET \
			--set *.args.K8S_VERSION=$(K8S_VERSION); \
	fi