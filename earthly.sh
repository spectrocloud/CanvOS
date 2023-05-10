#!/bin/bash

source .arg
docker run --privileged -v /var/run/docker.sock:/var/run/docker.sock --rm --env EARTHLY_BUILD_ARGS -t -v "$(pwd)":/workspace -v earthly-tmp:/tmp/earthly:rw earthly/earthly:v0.7.4 --allow-privileged "$@"
    
echo -e '  system.uri: "{{ .spectro.pack.edge-native-byoi.options.system.registry }}/{{ .spectro.pack.edge-native-byoi.options.system.repo }}:{{ .spectro.pack.edge-native-byoi.options.system.k8sDistribution }}-{{ .spectro.system.kubernetes.version }}-{{ .spectro.pack.edge-native-byoi.options.system.peVersion }}-{{ .spectro.pack.edge-native-byoi.options.system.customTag }}"'
echo -e '\n'
echo -e "  system.repo: $IMAGE_REGISTRY"
echo -e "  system.k8sDistribution: $K8S_DISTRIBUTION"
echo -e "  system.osName: $OS_DISTRIBUTION"
echo -e "  system.peVersion: $MY_ENVIRONMENT"
echo -e "  system.customTag: $CUSTOM_TAG"