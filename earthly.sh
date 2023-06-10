#!/bin/bash
PE_VERSION=$(git describe --abbrev=0 --tags)
source .arg

### Verify Depencies
# Check if Docker is installed 
if command -v docker >/dev/null 2>&1 ; then
    echo "version: $(docker -v)"
else
    echo "Docker not found.  Please use the guide for your platform located https://docs.docker.com/engine/install/ to install Docker."
fi
# Check if the current user has permission to run privileged containers
if ! docker run --rm --privileged alpine sh -c 'echo "Privileged container test"' &> /dev/null; then
    echo "Privileged containers are not allowed for the current user."
    exit 1
fi
# # Check If Earthly is installed
# if command -v earthly >/dev/null 2>&1 ; then
#     echo "version: $(earthly -v)"
# else
#     echo "Earthly not found.  Please use the guide for your platform located https://earthly.dev/get-earthly to install Earthly"
# fi
# for arg in "$@"
# do
#     earthly --push --platform=linux/amd64 $arg --PE_VERSION=$(git describe --abbrev=0 --tags)
# done
docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -v "$(pwd)":/workspace -v earthly-tmp:/tmp/earthly:rw gcr.io/spectro-images-public/earthly/earthly:v0.7.4 --allow-privileged "$@"

# Verify the command was successful
if [ $? -ne 0 ]; then
    echo "An error occurred while running the command."
    exit 1
fi
docker stop earthly-buildkitd && docker rm earthly-buildkitd

# Print the output for use in Palette Profile.
echo -e '##########################################################################################################'
echo -e '\nPASTE THE CONTENTS BELOW INTO YOUR CLUSTER PROFILE IN PALETTE REPLACING ALL THE CONTENTSY IN THE PROFILE\n'
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