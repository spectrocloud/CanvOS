-include .arg
export

.PHONY: base-image build-iso provider-image kairosify

PUSH ?= true
IS_UKI ?= false

base-image:
	docker buildx bake base-image

build-iso:
	docker buildx bake build-iso

provider-image:
	@if [ "$(IS_UKI)" = "true" ]; then \
        docker buildx bake provider-image-uki; \
    else \
        docker buildx bake provider-image; \
    fi

kairosify:
	docker buildx bake -f docker-bake-kairosify.hcl $(if $(filter true,$(PUSH)),--push) kairosify --print