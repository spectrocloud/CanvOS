#!/bin/bash

set -e

# Setup
# git checkout test-two-node-vmware
# vi .netrc
# ./test/test-two-node.sh

# edit these variables

# govc
export GOVC_USERNAME=<YOUR_NAME>@vsphere.local
export GOVC_PASSWORD=<YOUR_VSPHERE_PASSWORD>
export GOVC_URL=10.10.128.10
export GOVC_INSECURE=true
export GOVC_DATACENTER=Datacenter
export GOVC_DATASTORE=vsanDatastore2
export GOVC_NETWORK=VM-NETWORK
export GOVC_RESOURCE_POOL=<YOUR_RESOURCE_POOL>
export GOVC_FOLDER=<YOUR_FOLDER>

# isos
export HOST_SUFFIX=tyler # required to ensure unique edge host IDs
export ISO_FOLDER=<YOUR_FOLDER> e.g. "ISO/01-tyler"
export STYLUS_ISO="${ISO_FOLDER}/stylus-dev-amd64.iso"

# palette
export API_KEY=<YOUR_PALETTE_API_KEY>
export PROJECT_UID=<YOUR_PROJECT_ID>
export EDGE_REGISTRATION_TOKEN=<YOUR_REGISTRATION_TOKEN>
export DOMAIN=dev.spectrocloud.com
export CLUSTER_NAME=two-node
export PUBLIC_PACK_REPO_UID=5e2031962f090e2d3d8a3290

# images
export OCI_REGISTRY=ttl.sh

#####
# don't edit anything below
#####

declare -a vm_array=("two-node-one" "two-node-two")
export HOST_1="${vm_array[0]}-$HOST_SUFFIX"
export HOST_2="${vm_array[1]}-$HOST_SUFFIX"

function create_canvos_args() {
cat <<EOF > .arg
CUSTOM_TAG=twonode
IMAGE_REGISTRY=$OCI_REGISTRY
OS_DISTRIBUTION=ubuntu
IMAGE_REPO=ubuntu
OS_VERSION=22
K8S_DISTRIBUTION=k3s
ISO_NAME=palette-edge-installer
ARCH=amd64
HTTPS_PROXY=
HTTP_PROXY=
PROXY_CERT_PATH=
UPDATE_KERNEL=false
EOF
}

function create_userdata() {
cat <<EOF > build/user-data
#cloud-config
cluster:
  env:
    two-node: "true"
stylus:
  site:
    edgeHostToken: "$EDGE_REGISTRATION_TOKEN"
    name: "$1-$HOST_SUFFIX"
    paletteEndpoint: "$DOMAIN"
  debug: true
  twoNode:
    enabled: true
install:
  poweroff: true
users:
  - name: kairos
    passwd: kairos
EOF
echo "created build/user-data"
}

function create_vms() {
    for vm in "${vm_array[@]}"; do
        govc vm.create -m 8192 -c 4 -disk 100GB -net.adapter vmxnet3 -iso=$STYLUS_ISO -on=false -pool=$GOVC_RESOURCE_POOL $vm
        dev=$(govc device.cdrom.add -vm $vm)
        govc device.cdrom.insert -vm=$vm -device=$dev "${ISO_FOLDER}/user-data-${vm}.iso"
        govc vm.power -on $vm
    done
}

function destroy_vms() {
    for vm in "${vm_array[@]}"; do
        govc vm.destroy $vm
    done
}

function upload_userdata_isos() {
    for vm in "${vm_array[@]}"; do
        govc datastore.upload --ds=$GOVC_DATASTORE --dc=$GOVC_DATACENTER "build/user-data-${vm}.iso" "${ISO_FOLDER}/user-data-${vm}.iso"
    done
}

function upload_stylus_iso() {
    govc datastore.upload --ds=$GOVC_DATASTORE --dc=$GOVC_DATACENTER build/palette-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso $STYLUS_ISO
}

function wait_for_vms_to_power_off() {
    while true; do
        powerState1=$(govc vm.info -json=true "${vm_array[0]}" | jq -r .[][0].runtime.powerState)
        powerState2=$(govc vm.info -json=true "${vm_array[1]}" | jq -r .[][0].runtime.powerState)
        if [ "$powerState1" = "poweredOff" ] && [ "$powerState2" = "poweredOff" ]; then
            echo VMs powered off!
            break
        fi
        echo "VMs not powered off, sleeping for 5s..."
        sleep 5
    done
}

function reboot_vms() {
    for vm in "${vm_array[@]}"; do
        govc device.ls -vm=$vm
        govc vm.power -off -force $vm
        govc device.cdrom.eject -vm=$vm -device=cdrom-3000
        govc vm.power -on $vm
    done
}

function wait_until_edge_hosts_ready() {
    while true; do
        ready=$(curl -X POST https://$DOMAIN/v1/dashboard/edgehosts/search \
            -H "ApiKey: $API_KEY" \
            -H "Content-Type: application/json" \
            -H "ProjectUid: $PROJECT_UID" \
            -d \
        '
            {
                "filter": {
                    "conjuction": "and",
                    "filterGroups": [
                        {
                            "conjunction": "and",
                            "filters": [
                                {
                                    "property": "state",
                                    "type": "string",
                                    "condition": {
                                        "string": {
                                            "operator": "eq",
                                            "negation": false,
                                            "match": {
                                                "conjunction": "or",
                                                "values": [
                                                    "ready",
                                                    "unpaired"
                                                ]
                                            },
                                            "ignoreCase": false
                                        }
                                    }
                                }
                            ]
                        }
                    ]
                },
                "sort": []
            }
        ' | jq -e 'select(.items != []).items | map(. | select(.status.health.state == "healthy")) | length')

        if [ $ready = 2 ]; then
            echo Both Edge Hosts are healthy!
            break
        fi
        echo "Only $ready Edge Hosts are healthy, sleeping for 5s..."
        sleep 5
    done
}

function prepare_cluster_profile() {
    jq '
      .metadata.name = env.CLUSTER_NAME |
      .spec.template.packs[0].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[1].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[2].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.template.packs[0].values |= gsub("STYLUS_HASH"; env.STYLUS_HASH)
    ' test/templates/two-node-cluster-profile.json.tmpl > two-node-cluster-profile.json
}

function create_cluster_profile() {
    export CLUSTER_PROFILE_UID=$(curl -X POST https://$DOMAIN/v1/clusterprofiles/import?publish=true \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d @two-node-cluster-profile.json | jq -r .uid)
    rm -f two-node-cluster-profile.json
}

function prepare_cluster() {
    jq '
      .metadata.name = env.CLUSTER_NAME |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].hostUid = env.HOST_1 |
      .spec.machinePoolConfig[1].cloudConfig.edgeHosts[0].hostUid = env.HOST_2 |
      .spec.profiles[0].uid = env.CLUSTER_PROFILE_UID |
      .spec.profiles[0].packValues[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.profiles[0].packValues[0].values |= gsub("STYLUS_HASH"; env.STYLUS_HASH)
    ' test/templates/two-node-create.json.tmpl > two-node-create.json
}

function create_cluster() {
    curl -X POST https://$DOMAIN/v1/spectroclusters/edge-native?ProjectUid=$PROJECT_UID \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d @two-node-create.json
    rm -f two-node-create.json
}

function destroy_cluster() {
    clusterUid=$1
    curl -vvv -X PATCH https://$DOMAIN/v1/spectroclusters/$clusterUid/status/conditions \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d \
    '
        [
            {
                "message": "cleaned up",
                "reason": "CloudInfrastructureCleanedUp",
                "status": "True",
                "type": "CloudInfrastructureCleanedUp"
            }
        ]
    '
}

function create_iso() {
    touch meta-data
    mkisofs -output build/user-data-$2.iso -volid cidata -joliet -rock $1 meta-data
    rm -f meta-data
}

function create_userdata_isos() {
    for vm in "${vm_array[@]}"; do
        create_userdata $vm
        create_iso build/user-data $vm
    done
}

function build_provider_k3s() {
    echo "Build provider-k3s image"
    earthly +build-provider-package \
        --platform=linux/amd64 \
        --IMAGE_REPOSITORY=${OCI_REGISTRY} \
        --VERSION=${PROVIDER_K3S_HASH}
    docker push ${OCI_REGISTRY}/provider-k3s:${PROVIDER_K3S_HASH}
}

function build_stylus_package_and_framework() {
    echo "Build stylus image and stylus framework image"
    earthly --allow-privileged +package \
        --platform=linux/amd64 \
        --IMAGE_REPOSITORY=${OCI_REGISTRY} \
        --BASE_IMAGE=quay.io/kairos/core-opensuse-leap:v2.3.2 \
        --VERSION=v0.0.0-${STYLUS_HASH}
    docker push ${OCI_REGISTRY}/stylus-linux-amd64:v0.0.0-${STYLUS_HASH}
    docker push ${OCI_REGISTRY}/stylus-framework-linux-amd64:v0.0.0-${STYLUS_HASH}
}

function build_canvos() {
    echo "Build provider image & installer ISO"
    earthly +build-all-images \
        --ARCH=amd64 \
        --PROVIDER_BASE=${OCI_REGISTRY}/provider-k3s:${PROVIDER_K3S_HASH} \
        --STYLUS_BASE=${OCI_REGISTRY}/stylus-framework-linux-amd64:v0.0.0-${STYLUS_HASH} \
        --ISO_NAME=palette-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH} \
        --IMAGE_REGISTRY=${OCI_REGISTRY} \
        --TWO_NODE=true \
        --CUSTOM_TAG=twonode
    docker push ${OCI_REGISTRY}/ubuntu:k3s-1.26.4-v4.0.4-twonode
    docker push ${OCI_REGISTRY}/ubuntu:k3s-1.27.2-v4.0.4-twonode
}

function build_all() {

    test -d ../provider-k3s || ( cd .. && git clone https://github.com/kairos-io/provider-k3s -b two-node )
    cd ../provider-k3s
    export PROVIDER_K3S_HASH=$(git describe --always)

    (
        docker image ls --format "{{.Repository}}:{{.Tag}}" | \
        grep -q ${OCI_REGISTRY}/provider-k3s:${PROVIDER_K3S_HASH}
    ) || ( build_provider_k3s )

    test -d ../stylus || ( cd .. && git clone https://github.com/spectrocloud/stylus -b 2-node-health-checks )
    cd ../stylus
    export STYLUS_HASH=$(git describe --always)

    (
        docker image ls --format "{{.Repository}}:{{.Tag}}" | \
        grep -q $OCI_REGISTRY/stylus-linux-amd64:v0.0.0-${STYLUS_HASH}
    ) || ( build_stylus_package_and_framework )

    cd ../CanvOS
    test -f build/palette-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso || ( build_canvos )
}

function main() {

    build_all
    upload_stylus_iso
    create_userdata_isos
    upload_userdata_isos

    create_vms
    wait_for_vms_to_power_off
    reboot_vms
    wait_until_edge_hosts_ready

    if [ -z "${CLUSTER_PROFILE_UID}" ]; then
        prepare_cluster_profile
        create_cluster_profile
    fi

    prepare_cluster
    create_cluster

}

# This line and the if condition bellow allow sourcing the script without executing
# the main function
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced == 1 ]]; then
    set +e
    echo "You can now use any of these functions:"
    echo ""
    grep ^function  ${BASH_SOURCE[0]} | grep -v main | awk '{gsub(/function /,""); gsub(/\(\) \{/,""); print;}'
    echo
else
    main
fi

# vim: ts=4 sw=4 sts=4 et