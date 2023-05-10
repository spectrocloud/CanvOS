#!/bin/bash
PE_VERSION=$(git describe --abbrev=0 --tags)
source .arg
docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -v "$(pwd)":/workspace -v earthly-tmp:/tmp/earthly:rw earthly/earthly:v0.7.4 --allow-privileged "$@"

echo -e '###################################################################################################'
echo -e '\nPASTE THE CONTENTS BELOW INTO YOUR CLUSTER PROFILE IN PALETTE BELOW THE "OPTIONS" ATTRIBUTE\n'
echo -e '###################################################################################################'
echo -e '\n'
echo -e '  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"'
echo -e '\n'
echo -e "  system.registry: $IMAGE_REGISTRY"
echo -e "  system.repo: $IMAGE_REPO"
echo -e "  system.k8sDistribution: $K8S_DISTRIBUTION"
echo -e "  system.osName: $OS_DISTRIBUTION"
echo -e "  system.peVersion: $PE_VERSION"
echo -e "  system.customTag: $CUSTOM_TAG"
echo -e "  system.osVersion: $OS_VERSION"