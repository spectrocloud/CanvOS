-include .arg
export

.PHONY: base-image build-iso provider-image kairosify

PUSH ?= true

base-image:
	docker buildx bake base-image

iso:
	docker buildx bake build-iso

provider-image:
	docker buildx bake provider-image

kairosify:
	docker buildx bake -f docker-bake-kairosify.hcl $(if $(filter true,$(PUSH)),--push) kairosify --print