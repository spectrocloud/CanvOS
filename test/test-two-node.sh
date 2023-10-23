#!/bin/bash

set -e

# edit these variables

OCI_REGISTRY=ozspectro
CANVOS_VM_VCPU=${CANVOS_VM_VCPU:-4}
CANVOS_VM_DISK=${CANVOS_VM_DISK:-35}
CANVOS_VM_RAM=${CANVOS_VM_RAM:-8192}
CANVOS_VM_OSINFO=${CANVOS_VM_OSINFO:-ubuntujammy}
CANVOS_VM_CDROM=${CANVOS_VM_CDROM:-build/palette-edge-installer.iso}

EDGEHOST_REGISRATION_KEY=
PALETTE_ENDPOINT=tylerdev-spectrocloud.console.spectrocloud.com

declare -a VM_ARRAY=("two-node-one" "two-node-two")

#####
# don't edit anything below
#####

function create_user_data(){
    export MACHINENAME=$1
    export EDGEHOST_REGISRATION_KEY
    export PALETTE_ENDPOINT
    envsubst < test/templates/user-data.tmpl > user-data
}

function prepare_user_data_iso(){
    local userdata=$1
    test -f site-user-data.iso && rm -f site-user-data.iso
    touch meta-data
    mkisofs -output site-user-data.iso -volid cidata \
        -joliet -rock ${userdata} meta-data
}

function start_machine(){
    local NAME=$1
    local INSTALLER_DISK=$2
    virt-install \
        --osinfo ${CANVOS_VM_OSINFO} \
        --name ${NAME} \
        --cdrom ${INSTALLER_DIS} \
        --memory ${CANVOS_VM_RAM} \
        --vcpu ${CANVOS_VM_VCPU} \
        --disk size=${CANVOS_VM_DISK} \
        --disk "site-user-data.iso",device=cdrom \
        --virt-type kvm \
        --network two-node
        --noautoconsole \
        --import 
}

function prepare_network(){
    if [ $(virsh net-list | grep two-node | awk '{print $2}') != 'active' ]; then
        virsh net-define test/two-node-network.xml
    fi
}

function build_provider_k3s(){
	echo "Build provider k3s"
	earthly +build-provider-package --IMAGE_REPOSITORY=${OCI_REGISTRY} --VERSION=${PROVIDER_K3S_HASH}
	docker push $OCI_REGISTRY/provider-k3s:v0.0.0-${PROVIDER_K3S_HASH}
}

function build_stylus_package_and_framework(){ 
	echo "Build Stylus image and framework"
	earthly --push --allow-privileged +package --IMAGE_REPOSITORY=${OCI_REGISTRY} \
    --platform=linux/amd64 \
    --BASE_IMAGE=quay.io/kairos/core-opensuse-leap:v2.3.2 \
    --VERSION=v0.0.0-twonode

	docker push $OCI_REGISTRY/stylus-linux-amd64:v0.0.0-${STYLUS_HASH}
	docker push $OCI_REGISTRY/stylus-framework-linux-amd64:v0.0.0-twonode
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
    
    curl -X POST https://$domain/v1/clusterporfiles/import?publish=true \
        -H "ApiKey: $apiKey" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $projectUid" \
        -d @two-node-cluster-profile.json
}


function build_all(){

    cd ../provider-k3s
    PROVIDER_K3S_HASH=$(git describe --always)
    ( docker image ls --format "{{.Repository}}:{{.Tag}}"  | \
        grep -q ${OCI_REGISTRY}/provider-k3s:v0.0.0-${PROVIDER_K3S_HASH} ) \
    	|| ( build_provider_k3s )
    
    cd ../stylus
    STYLUS_HASH=$(git describe --always)
    
    ( docker image ls --format "{{.Repository}}:{{.Tag}}" | \
         grep -q $OCI_REGISTRY/stylus-linux-amd64:v0.0.0-${STYLUS_HASH} ) \
         || ( build_stylus_package_and_framework )
    
    cd ../CanvOS
    
    test -f build/pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso || \
	( echo "Build ISO" && \    
    	  earthly +build-all-images --ARCH=amd64 \
    	        --PROVIDER_BASE=${OCI_REGISTRY}/provider-k3s:v0.0.0-${PROVIDER_K3S_HASH} \
    	        --STYLUS_BASE=${OCI_REGISTRY}/stylus-framework-linux-amd64:twonode \
    		    --ISO_NAME=pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH} \
    		    --IMAGE_REGISTRY=${OCI_REGISTRY} \
    	        --TWO_NODE=true --CUSTOM_TAG=twonode
         docker push ${OCI_REGISTRY}/ubuntu:k3s-1.27.2-v4.0.4-twonode )
}

function launch_all_vms(){
    for vm in "${VM_ARRAY[@]}"; do
        create_user_data $vm
        prepare_user_data_iso user-data
        start_machine $vm pallete-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}
    done
}

function main(){

    build_all
    launch_all_vms

    echo "Machines launched, waiting for the machines to register ..."
    echo "In the mean while you should update your cluster profile ..."
    echo "Once the machine registers, press Enter to create  a cluster with these machines"
    
    prepare_cluster_profile
    create_cluster_profile

    read -p "When both machines are ready, press enter to launch the cluster"
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

# vim: ts=4 sw=4 sts=4 et 
