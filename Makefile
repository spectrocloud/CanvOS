DOCKER_USERNAME ?= 3pings
APPLICATION_NAME ?= hello-world
GIT_HASH ?= $(shell git log --format="%h" -n 1)

_BUILD_ARGS_TAG ?= ${GIT_HASH}
_BUILD_ARGS_RELEASE_TAG ?= latest
_BUILD_ARGS_DOCKERFILE ?= Dockerfile
_BUILD_ARGS_NAME ?=

_builder:
	docker build --tag ${DOCKER_USERNAME}/${APPLICATION_NAME}:${_BUILD_ARGS_TAG} -f ${_BUILD_ARGS_DOCKERFILE} ./base_images

_pusher:
	docker push ${DOCKER_USERNAME}/${APPLICATION_NAME}:${_BUILD_ARGS_TAG}

_releaser:
	docker pull ${DOCKER_USERNAME}/${APPLICATION_NAME}:${_BUILD_ARGS_TAG}
	docker tag  ${DOCKER_USERNAME}/${APPLICATION_NAME}:${_BUILD_ARGS_TAG} ${DOCKER_USERNAME}/${APPLICATION_NAME}:latest
	docker push ${DOCKER_USERNAME}/${APPLICATION_NAME}:${_BUILD_ARGS_RELEASE_TAG}

build:
	$(MAKE) _builder

push:
	$(MAKE) _pusher

release:
	$(MAKE) _releaser

build_%:
	$(MAKE) _builder \
		-e _BUILD_ARGS_TAG="$*-${GIT_HASH}" \
		-e _BUILD_ARGS_DOCKERFILE="Dockerfile.$*"

push_%:
	$(MAKE) _pusher \
		-e _BUILD_ARGS_TAG="$*-${GIT_HASH}"

release_%:
	$(MAKE) _releaser \
		-e _BUILD_ARGS_TAG="$*-${GIT_HASH}" \
		-e _BUILD_ARGS_RELEASE_TAG="$*-latest"


img: 
	./scripts/installer.sh ubuntu-lts-22-k3s


_installer:
	./scripts/installer.sh
installer:
	$(MAKE) _installer
installer_%:
	$(MAKE) _installer ubuntu-lts-22-k3s