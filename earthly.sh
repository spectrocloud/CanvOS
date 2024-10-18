#!/bin/bash
# Uncomment the line below to enable debug mode
# set -x

function build_with_proxy() {
    export HTTP_PROXY=$HTTP_PROXY
    export HTTPS_PROXY=$HTTPS_PROXY
    gitconfig=$(envsubst <.gitconfig.template | base64 | tr -d '\n')
    # cleanup any previous earthly-buildkitd
    if [ "$(docker container inspect -f '{{.State.Running}}' earthly-buildkitd)" = "true" ]; then
        docker stop earthly-buildkitd
    fi
    # start earthly buildkitd
    docker run -d --privileged \
        --name earthly-buildkitd \
        -v ~/.docker/config.json:/root/.docker/config.json \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --rm -t \
        -e GLOBAL_CONFIG="$global_config" \
        -e BUILDKIT_TCP_TRANSPORT_ENABLED=true \
        -e http_proxy=$HTTP_PROXY \
        -e https_proxy=$HTTPS_PROXY \
        -e HTTPS_PROXY=$HTTPS_PROXY \
        -e HTTP_PROXY=$HTTP_PROXY \
        -e NO_PROXY=$NO_PROXY \
        -e no_proxy=$NO_PROXY \
        -e EARTHLY_GIT_CONFIG=$gitconfig \
        -v "$PROXY_CERT_PATH:/usr/local/share/ca-certificates/sc.crt:ro" \
        -v earthly-tmp:/tmp/earthly:rw \
        -p 8372:8372 \
        $SPECTRO_PUB_REPO/third-party/edge/earthly/buildkitd:$EARTHLY_VERSION
    # Update the CA certificates in the container
    docker exec -it earthly-buildkitd update-ca-certificates

    # Run Earthly in Docker to create artifacts  Variables are passed from the .arg file
    docker run --privileged \
        -v ~/.docker/config.json:/root/.docker/config.json \
        -v /var/run/docker.sock:/var/run/docker.sock \
        --rm --env EARTHLY_BUILD_ARGS -t \
        -e GLOBAL_CONFIG="$global_config" \
        -e EARTHLY_BUILDKIT_HOST=tcp://0.0.0.0:8372 \
        -e BUILDKIT_TLS_ENABLED=false \
        -e http_proxy=$HTTP_PROXY \
        -e https_proxy=$HTTPS_PROXY \
        -e HTTPS_PROXY=$HTTPS_PROXY \
        -e HTTP_PROXY=$HTTP_PROXY \
        -e NO_PROXY=$NO_PROXY \
        -e no_proxy=$NO_PROXY \
        -v "$(pwd)":/workspace \
        -v "$PROXY_CERT_PATH:/workspace/sc.crt:ro" \
        --entrypoint /workspace/earthly-entrypoint.sh \
        $SPECTRO_PUB_REPO/third-party/edge/earthly/earthly:$EARTHLY_VERSION --allow-privileged "$@"
}

function build_without_proxy() {
    # Run Earthly in Docker to create artifacts  Variables are passed from the .arg file
    docker run --privileged -v ~/.docker/config.json:/root/.docker/config.json -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -e GLOBAL_CONFIG="$global_config" -v "$(pwd)":/workspace $SPECTRO_PUB_REPO/third-party/edge/earthly/earthly:$EARTHLY_VERSION --allow-privileged "$@"
}

function print_os_pack() {
    # Print the output for use in Palette Profile.
    echo -e '##########################################################################################################'
    echo -e '\nPASTE THE CONTENT BELOW INTO YOUR CLUSTER PROFILE IN PALETTE REPLACING ALL THE CONTENTS IN THE PROFILE\n'
    echo -e '##########################################################################################################'
    echo -e '\n'
    echo -e 'pack:'
    echo -e '  content:'
    echo -e '    images:'
    echo -e '      - image: "{{.spectro.pack.edge-native-byoi.options.system.uri}}"'
    echo -e '  # Below config is default value, please uncomment if you want to modify default values'
    echo -e '  #drain:'
    echo -e '    #cordon: true'
    echo -e '    #timeout: 60 # The length of time to wait before giving up, zero means infinite'
    echo -e '    #gracePeriod: 60 # Period of time in seconds given to each pod to terminate gracefully. If negative, the default value specified in the pod will be used'
    echo -e '    #ignoreDaemonSets: true'
    echo -e '    #deleteLocalData: true # Continue even if there are pods using emptyDir (local data that will be deleted when the node is drained)'
    echo -e '    #force: true # Continue even if there are pods that do not declare a controller'
    echo -e '    #disableEviction: false # Force drain to use delete, even if eviction is supported. This will bypass checking PodDisruptionBudgets, use with caution'
    echo -e '    #skipWaitForDeleteTimeout: 60 # If pod DeletionTimestamp older than N seconds, skip waiting for the pod. Seconds must be greater than 0 to skip.'
    echo -e 'options:'
    echo -e '  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"'
    echo -e '\n'
    echo -e "  system.registry: $IMAGE_REGISTRY"
    echo -e "  system.repo: $IMAGE_REPO"
    echo -e "  system.k8sDistribution: $K8S_DISTRIBUTION"
    echo -e "  system.osName: $OS_DISTRIBUTION"
    echo -e "  system.peVersion: $PE_VERSION"
    echo -e "  system.customTag: $CUSTOM_TAG"
    echo -e "  system.osVersion: $OS_VERSION"
}

global_config="{disable_analytics: true}"
PE_VERSION=$(git describe --abbrev=0 --tags)
SPECTRO_PUB_REPO=us-docker.pkg.dev/palette-images
EARTHLY_VERSION=v0.8.15
source .arg
ALPINE_IMG=$SPECTRO_PUB_REPO/edge/canvos/alpine:3.20
### Verify Dependencies
# Check if Docker is installed
if command -v docker >/dev/null 2>&1; then
    echo "version: $(docker -v)"
else
    echo "Docker not found.  Please use the guide for your platform located https://docs.docker.com/engine/install/ to install Docker."
fi
# Check if the current user has permission to run privileged containers
if ! docker run --rm --privileged $ALPINE_IMG sh -c 'echo "Privileged container test"' &>/dev/null; then
    echo "Privileged containers are not allowed for the current user."
    exit 1
fi
if [ -z "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY"]; then
    build_without_proxy "$@"
else
    build_with_proxy "$@"
fi

# Verify the command was successful
if [ $? -ne 0 ]; then
    echo "An error occurred while running the command."
    exit 1
fi
# Cleanup builder helper images.
docker rmi $SPECTRO_PUB_REPO/third-party/edge/earthly/earthly:$EARTHLY_VERSION
if [ "$(docker container inspect -f '{{.State.Running}}' earthly-buildkitd)" = "true" ]; then
    docker stop earthly-buildkitd
fi
docker rmi $SPECTRO_PUB_REPO/third-party/edge/earthly/buildkitd:$EARTHLY_VERSION 2>/dev/null
docker rmi $ALPINE_IMG

if [[ "$1" == "+uki-genkey" ]]; then
    ./keys.sh secure-boot/
fi

# if $1 is in one of the following values, print the output for use in Palette Profile.
targets=("+build-provider-images" "+build-provider-images-fips" "+build-all-images")
for arg in "${targets[@]}"; do
    if [[ "$1" == "$arg" ]]; then
        print_os_pack
    fi
done
