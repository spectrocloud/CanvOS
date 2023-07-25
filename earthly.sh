#!/bin/bash
function build_with_proxy() {
    export HTTP_PROXY=$HTTP_PROXY
    export HTTPS_PROXY=$HTTPS_PROXY
    gitconfig=$(envsubst <gitconfig | base64 | tr -d '\n')
    # cleanup any previous earthly-buildkitd
    if [ "$( docker container inspect -f '{{.State.Running}}' earthly-buildkitd )" = "true" ]; then 
        docker stop earthly-buildkitd
    fi
    # start earthly buildkitd
    docker run -d --privileged --name earthly-buildkitd -v /var/run/docker.sock:/var/run/docker.sock --rm -t -e BUILDKIT_TCP_TRANSPORT_ENABLED=true -e http_proxy=$HTTP_PROXY -e https_proxy=$HTTPS_PROXY -e HTTPS_PROXY=$HTTPS_PROXY -e HTTP_PROXY=$HTTP_PROXY -e NO_PROXY=$NO_PROXY -e no_proxy=$no_proxy -e EARTHLY_GIT_CONFIG=$gitconfig -v "$PROXY_CERT_PATH:/usr/local/share/ca-certificates/sc.crt:ro" -v earthly-tmp:/tmp/earthly:rw -p 8372:8372 gcr.io/spectro-images-public/earthly/buildkitd:$EARTHLY_VERSION
    # Update the CA certificates in the container
    docker exec -it earthly-buildkitd update-ca-certificates

    # Run Earthly in Docker to create artifacts  Variables are passed from the .arg file
    docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -e EARTHLY_BUILDKIT_HOST=tcp://0.0.0.0:8372 -e BUILDKIT_TLS_ENABLED=false -v "$(pwd)":/workspace gcr.io/spectro-images-public/earthly/earthly:$EARTHLY_VERSION --allow-privileged "$@"
}

function build_without_proxy() {
    # Run Earthly in Docker to create artifacts  Variables are passed from the .arg file
    docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -v "$(pwd)":/workspace gcr.io/spectro-images-public/earthly/earthly:$EARTHLY_VERSION --allow-privileged "$@"
}

PE_VERSION=$(git describe --abbrev=0 --tags)
EARTHLY_VERSION=v0.7.4
source .arg

### Verify Depencies
# Check if Docker is installed
if command -v docker >/dev/null 2>&1; then
    echo "version: $(docker -v)"
else
    echo "Docker not found.  Please use the guide for your platform located https://docs.docker.com/engine/install/ to install Docker."
fi
# Check if the current user has permission to run privileged containers
if ! docker run --rm --privileged alpine sh -c 'echo "Privileged container test"' &>/dev/null; then
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
docker rmi gcr.io/spectro-images-public/earthly/earthly:$EARTHLY_VERSION
docker rmi gcr.io/spectro-images-public/earthly/buildkitd:$EARTHLY_VERSION
docker rmi alpine:latest

# Print the output for use in Palette Profile.
echo -e '##########################################################################################################'
echo -e '\nPASTE THE CONTENTS BELOW INTO YOUR CLUSTER PROFILE IN PALETTE REPLACING ALL THE CONTENTS IN THE PROFILE\n'
echo -e '##########################################################################################################'
echo -e '\n'
echo -e 'pack:'
echo -e '  content:'
echo -e '    images:'
echo -e '      - image: "{{.spectro.pack.edge-native-byoi.options.system.uri}}"'
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
