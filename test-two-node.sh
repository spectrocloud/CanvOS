#!/bin/bash

set -e

OCI_REGISTRY=ozspectro

function build_provider_k3s(){
	echo "Build provider k3s"
	earthly +build-provider-package --IMAGE_REPOSITORY=${OCI_REGISTRY} --VERSION=${PROVIDER_K3S_HASH}
	docker push $OCI_REGISTRY/provider-k3s:v0.0.0-${PROVIDER_K3S_HASH}
}

function build_stylus_package(){ 
	echo "Build Stylus"
	earthly --push +package --IMAGE_REPOSITORY=${OCI_REGISTRY}
	docker push $OCI_REGISTRY/stylus-linux-amd64:v0.0.0-${STYLUS_HASH}
	docker push $OCI_REGISTRY/stylus-framework-linux-amd64:v0.0.0-${STYLUS_HASH}
}


function create_cluster(){
    apiKey=""
    projectUid="650ab2782df5377f52bb7cc0"
    domain=tylerdev-spectrocloud.console.spectrocloud.com
    
    curl -X POST https://$domain/v1/spectroclusters/edge-native?ProjectUid=$projectUid \
        -H "ApiKey: $apiKey" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $projectUid" \
        -d @two-node-create.json
}

function prepare_cluster_profile(){
    jq '.metadata.name = env.CLUSTER_NAME | .spec.template.packs[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) ' two-node-cluster-profile.json.tmpl > two-node-cluster-profile
}

function create_cluster_profile(){
    apiKey=""
    projectUid="650ab2782df5377f52bb7cc0"
    domain=tylerdev-spectrocloud.console.spectrocloud.com
    
    https://api.spectrocloud.com/v1/clusterprofiles/import
    curl -X POST https://$domain/v1/clusterporfiles/import?publish=true \
        -H "ApiKey: $apiKey" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $projectUid" \
        -d @two-node-cluster-profile.json
}

function create_user_data(){
	MACHINE=$1
	cat << EOF>user-data
#cloud-config

cluster:
  env:
    two-node: "true"

stylus:
  site:
    edgeHostToken: ...
    name: two-node-oz-${MACHINE}
    paletteEndpoint: api.spectrocloud.com
  debug: true
  twoNode:
    provider: k3s
    
install:
  poweroff: true

users:
  - name: kairos
    passwd: kairos
EOF
}


function main(){
   
    cd ../provider-k3s
   
    PROVIDER_K3S_HASH=$(git describe --always)
   

    ( docker image ls --format "{{.Repository}}:{{.Tag}}"  | grep -q ${OCI_REGISTRY}/provider-k3s:v0.0.0-${PROVIDER_K3S_HASH} ) \
    	|| ( build_provider_k3s )
    
    cd ../stylus
    
    STYLUS_HASH=$(git describe --always)
    
    ( docker image ls --format "{{.Repository}}:{{.Tag}}" | grep -q $OCI_REGISTRY/stylus-linux-amd64:v0.0.0-${STYLUS_HASH} ) || ( build_stylus_package )
    
    
    cd ../CanvOS
    
    test -f build/pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso || \
    	earthly +build-all-images --ARCH=amd64 \
    	        --PROVIDER_BASE=${OCI_REGISTRY}/provider-k3s:v0.0.0-${PROVIDER_K3S_HASH} \
    	        --STYLUS_BASE=${OCI_REGISTRY}/stylus-framework-linux-amd64:twonode \
    		--ISO_NAME=pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH} \
    		--IMAGE_REGISTRY=${OCI_REGISTRY} \
    	        --TWO_NODE=true --CUSTOM_TAG=twonode
    
    
    MACHINE1="1"
    MACHINE2="2"
    
    
    create_user_data ${MACHINE1}
    bash launch-canvos-vm.sh -i build/pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso \
    	 -u user-data -n ${MACHINE1}
    
    create_user_data ${MACHINE2}
    bash launch-canvos-vm.sh -i build/pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso \
    	-u user-data -n ${MACHINE2}
    
    echo "Machines launched, waiting for the machines to register ..."
    echo "In the mean while you should update your cluster profile ..."
    echo "Once the machine registers, press Enter to create  a cluster with these machines"
    read -p "Feed the cluster Profile UID here:" CLUSTER_PROFILE
    
    CLUSTER_PROFILE="652e868c07222573d23ea26a"
    export CLUSTER_PROFILE
    
    jq '.spec.profiles[0] = env.CLUSTER_PROFILE | .metadata.name = "test-two-node-oz"' two-node-create.json
    create_cluster
}

# This line and the if condition bellow allow sourcing the script without executing
# the main function
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced == 1 ]]; then
    set +e
    echo "You can now use any of these functions:"
    echo ""
    grep ^function  ${BASH_SOURCE[0]} | grep -v main | awk '{gsub(/function /,""); gsub(/\(\)\{/,""); print;}'
else
    main
fi
