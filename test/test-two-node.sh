#!/bin/bash

set -e

# Usage
# -----
#
# 1. Install prerequisites:
#    - docker (https://docs.docker.com/engine/install/)
#    - earthly (https://earthly.dev/get-earthly)
#    - git (https://github.com/git-guides/install-git)
#    - govc (https://github.com/vmware/govmomi/blob/main/govc/README.md#installation)
#    - jq (https://jqlang.github.io/jq/download/)
#    - mkisofs (https://command-not-found.com/mkisofs)
#
# 2. Clone CanvOS and checkout this branch.
#
# 3. Create a .netrc file in the CanvOS repo root with GitHub
#    credentials capable of cloning Spectro Cloud internal repos
#    (required for building stylus).
#
# 4. Copy the test/env.example file to test/.env and edit test/.env
#    as required.
#
# 5. Source and execute this script:
#
#    source ./test/test-two-node.sh
#    ./test/test-two-node.sh

# Do not edit anything below

(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced == 0 ]]; then
    envfile=$(dirname "${0}")/.env
    if [ -f "${envfile}" ]; then
        source "${envfile}"
    else
        echo "Please create a .env file in the test directory and populate it with the required variables."
        exit 1
    fi
fi

declare -a vm_array=("2n1-$HOST_SUFFIX" "2n2-$HOST_SUFFIX")
export HOST_1="${vm_array[0]}"
export HOST_2="${vm_array[1]}"


echo ${vm_array[@]}

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
  providerConfig:
    two-node: "true"
    cluster-init: "no"
    datastore-endpoint: "http://localhost:2379"
stylus:
  site:
    edgeHostToken: "$EDGE_REGISTRATION_TOKEN"
    name: "$1"
    paletteEndpoint: "$DOMAIN"
  debug: true
  twoNode:
    enabled: true
    backend: "${TWO_NODE_BACKEND}"
    livenessSeconds: 30
install:
  poweroff: true
users:
  - name: kairos
    passwd: kairos
EOF
echo "created build/user-data"
}

function create_iso() {
    touch meta-data
    mkisofs -output build/user-data-$2.iso -volid cidata -joliet -rock $1 meta-data
    rm -f meta-data
}

function create_userdata_isos() {
    echo Creating user-data ISOs...
    for vm in "${vm_array[@]}"; do
        create_userdata $vm
        create_iso build/user-data $vm
    done
}

function upload_userdata_isos() {
    echo Uploading user-data ISOs...
    for vm in "${vm_array[@]}"; do
        govc datastore.upload --ds=$GOVC_DATASTORE --dc=$GOVC_DATACENTER "build/user-data-${vm}.iso" "${ISO_FOLDER}/user-data-${vm}.iso"
    done
}

function upload_stylus_iso() {
    iso=palette-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso
    echo Uploading installer ISO $iso...
    govc datastore.upload --ds=$GOVC_DATASTORE --dc=$GOVC_DATACENTER build/$iso $STYLUS_ISO
}

function create_vms() {
    echo Creating VMs...
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

function wait_for_vms_to_power_off() {
    echo Waiting for both VMs to be flashed and power off...
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
    echo "Ejecting installer ISO & rebooting VMs..."
    for vm in "${vm_array[@]}"; do
        govc device.ls -vm=$vm
        govc vm.power -off -force $vm
        govc device.cdrom.eject -vm=$vm -device=cdrom-3000
        govc device.cdrom.eject -vm=$vm -device=cdrom-3001
        govc vm.power -on $vm
    done
}

function wait_until_edge_hosts_ready() {
    echo Waiting for both Edge Hosts to register and become healthy...
    while true; do
        set +e
        ready=$(curl -s -X POST https://$DOMAIN/v1/dashboard/edgehosts/search \
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
        set -e
        if [ -z ${ready} ]; then
            ready=0
        fi
        if [ $ready = 2 ]; then
            echo Both Edge Hosts are healthy!
            break
        fi
        echo "Only $ready/2 Edge Hosts are healthy, sleeping for 5s..."
        sleep 5
    done
}

function destroy_edge_hosts() {
    readarray -t edgeHosts < <(curl -s -X POST https://$DOMAIN/v1/dashboard/edgehosts/search \
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
    ' | jq -r '.items[].metadata.uid')
    for host in "${edgeHosts[@]}"; do
        curl -s -X DELETE https://$DOMAIN/v1/edgehosts/$host \
            -H "ApiKey: $API_KEY" \
            -H "Content-Type: application/json" \
            -H "ProjectUid: $PROJECT_UID"
        echo Deleted Edge Host $host
    done
}

function prepare_cluster_profile() {
    if [ -z "${STYLUS_HASH}" ]; then
        echo STYLUS_HASH is unset. Please execute build_all and retry.
        return 1
    fi
    jq '
      .metadata.name = env.CLUSTER_NAME |
      .spec.template.packs[0].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[1].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[2].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.template.packs[0].values |= gsub("PE_VERSION"; env.PE_VERSION) |
      .spec.template.packs[0].values |= gsub("K3S_VERSION"; "1.26.4") |
      .spec.template.packs[0].values |= gsub("STYLUS_HASH"; env.STYLUS_HASH)
    ' test/templates/two-node-cluster-profile.json.tmpl > two-node-cluster-profile.json
}

function create_cluster_profile() {
    export CLUSTER_PROFILE_UID=$(curl -s -X POST https://$DOMAIN/v1/clusterprofiles/import?publish=true \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d @two-node-cluster-profile.json | jq -r .uid)
    rm -f two-node-cluster-profile.json
    if [ "$CLUSTER_PROFILE_UID" = "null" ]; then
        echo Cluster Profile creation failed as it already exists. Please delete it and retry.
        return 1
    fi
    echo "Cluster Profile $CLUSTER_PROFILE_UID created"
}

function destroy_cluster_profile() {
    curl -s -X DELETE https://$DOMAIN/v1/clusterprofiles/$CLUSTER_PROFILE_UID \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID"
    echo "Cluster Profile $CLUSTER_PROFILE_UID deleted"
}

function prepare_master_master_cluster() {
    if [ -z "${STYLUS_HASH}" ]; then
        echo STYLUS_HASH is unset. Please execute build_all and retry.
        return 1
    fi
    if nslookup $CLUSTER_VIP >/dev/null; then
        echo CLUSTER_VIP: $CLUSTER_VIP is allocated. Please retry with an unallocated VIP.
        return 1
    fi
    jq '
      .metadata.name = env.CLUSTER_NAME |
      .spec.cloudConfig.controlPlaneEndpoint.host = env.CLUSTER_VIP |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].hostUid = env.HOST_1 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].nicName = env.NIC_NAME |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[1].hostUid = env.HOST_2 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[1].nicName = env.NIC_NAME |
      .spec.profiles[0].uid = env.CLUSTER_PROFILE_UID |
      .spec.profiles[0].packValues[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.profiles[0].packValues[0].values |= gsub("PE_VERSION"; env.PE_VERSION) |
      .spec.profiles[0].packValues[0].values |= gsub("K3S_VERSION"; "1.26.4") |
      .spec.profiles[0].packValues[0].values |= gsub("STYLUS_HASH"; env.STYLUS_HASH)
    ' test/templates/two-node-master-master.json.tmpl > two-node-create.json
}

function prepare_master_worker_cluster() {
    if [ -z "${STYLUS_HASH}" ]; then
        echo STYLUS_HASH is unset. Please execute build_all and retry.
        return 1
    fi
    if nslookup $CLUSTER_VIP >/dev/null; then
        echo CLUSTER_VIP: $CLUSTER_VIP is allocated. Please retry with an unallocated VIP.
        return 1
    fi
    jq '
      .metadata.name = env.CLUSTER_NAME |
      .spec.cloudConfig.controlPlaneEndpoint.host = env.CLUSTER_VIP |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].hostUid = env.HOST_1 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].nicName = env.NIC_NAME |
      .spec.machinePoolConfig[1].cloudConfig.edgeHosts[0].hostUid = env.HOST_2 |
      .spec.machinePoolConfig[1].cloudConfig.edgeHosts[0].nicName = env.NIC_NAME |
      .spec.profiles[0].uid = env.CLUSTER_PROFILE_UID |
      .spec.profiles[0].packValues[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.profiles[0].packValues[0].values |= gsub("PE_VERSION"; env.PE_VERSION) |
      .spec.profiles[0].packValues[0].values |= gsub("K3S_VERSION"; "1.26.4") |
      .spec.profiles[0].packValues[0].values |= gsub("STYLUS_HASH"; env.STYLUS_HASH)
    ' test/templates/two-node-master-worker.json.tmpl > two-node-create.json
}

function create_cluster() {
    uid=$(curl -s -X POST https://$DOMAIN/v1/spectroclusters/edge-native?ProjectUid=$PROJECT_UID \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d @two-node-create.json | jq -r .uid)
    rm -f two-node-create.json
    echo Cluster $uid created
}

function destroy_cluster() {
    clusterUid=$1
    curl -s -X PATCH https://$DOMAIN/v1/spectroclusters/$clusterUid/status/conditions \
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
    echo "Cluster $clusterUid deleted"
}

function build_provider_k3s() {
    echo "Building provider-k3s image..."
    earthly +build-provider-package \
        --platform=linux/amd64 \
        --IMAGE_REPOSITORY=${OCI_REGISTRY} \
        --VERSION=${PROVIDER_K3S_HASH}
    docker push ${OCI_REGISTRY}/provider-k3s:${PROVIDER_K3S_HASH}
}

function build_stylus_package_and_framework() {
    echo "Building stylus image and stylus framework image..."
    earthly --allow-privileged +package \
        --platform=linux/amd64 \
        --IMAGE_REPOSITORY=${OCI_REGISTRY} \
        --BASE_IMAGE=quay.io/kairos/core-opensuse-leap:v2.3.2 \
        --VERSION=v0.0.0-${STYLUS_HASH}
    docker push ${OCI_REGISTRY}/stylus-linux-amd64:v0.0.0-${STYLUS_HASH}
    docker push ${OCI_REGISTRY}/stylus-framework-linux-amd64:v0.0.0-${STYLUS_HASH}
}

function build_canvos() {
    echo "Building provider image & installer ISO..."
    earthly +build-all-images \
        --ARCH=amd64 \
        --PROVIDER_BASE=${OCI_REGISTRY}/provider-k3s:${PROVIDER_K3S_HASH} \
        --STYLUS_BASE=${OCI_REGISTRY}/stylus-framework-linux-amd64:v0.0.0-${STYLUS_HASH} \
        --ISO_NAME=palette-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH} \
        --IMAGE_REGISTRY=${OCI_REGISTRY} \
        --TWO_NODE=true \
        --TWO_NODE_BACKEND=${TWO_NODE_BACKEND} \
        --CUSTOM_TAG=${STYLUS_HASH} \
	--PE_VERSION=v${PE_VERSION}
    docker push ${OCI_REGISTRY}/ubuntu:k3s-1.26.4-v${PE_VERSION}-${STYLUS_HASH}
}

function build_all() {

    # optionally build/rebuild provider-k3s
    test -d ../provider-k3s || ( cd .. && git clone https://github.com/kairos-io/provider-k3s -b ${PROVIDER_K3S_BRANCH})
    cd ../provider-k3s
    export PROVIDER_K3S_HASH=$(git describe --always)
    (
        docker image ls --format "{{.Repository}}:{{.Tag}}" | \
        grep -q ${OCI_REGISTRY}/provider-k3s:${PROVIDER_K3S_HASH}
    ) || ( build_provider_k3s )

    # optionally build/rebuild stylus images
    test -d ../stylus || ( cd .. && git clone https://github.com/spectrocloud/stylus -b ${STYLUS_BRANCH} )
    cd ../stylus
    export STYLUS_HASH=$(git describe --always)
    (
        docker image ls --format "{{.Repository}}:{{.Tag}}" | \
        grep -q $OCI_REGISTRY/stylus-linux-amd64:v0.0.0-${STYLUS_HASH}
    ) || ( build_stylus_package_and_framework )

    # optionally build/rebuild provider image & installer ISO
    cd ../CanvOS
    (
        test -f build/palette-edge-installer-stylus-${STYLUS_HASH}-k3s-${PROVIDER_K3S_HASH}.iso && \
        docker image ls --format "{{.Repository}}:{{.Tag}}" | \
        grep -q ${OCI_REGISTRY}/ubuntu:k3s-1.26.4-v${PE_VERSION}-${STYLUS_HASH}
    ) || ( build_canvos )
}

function clean_all() {
    docker images | grep $OCI_REGISTRY | awk '{print $3;}' | xargs docker rmi --force
    docker images | grep palette-installer | awk '{print $3;}' | xargs docker rmi --force
    earthly prune --reset
    docker system prune --all --volumes --force
}

function main() {

    # build all required edge artifacts
    build_all

    # upload installer ISO to vSphere
    upload_stylus_iso

    # create & upload user-data ISOs, configured to enable two node mode
    create_userdata_isos
    upload_userdata_isos

    # create VMs in vSphere, wait for the installation phase to complete,
    # then power them off, remove the installer ISO, and reboot them
    create_vms
    wait_for_vms_to_power_off
    reboot_vms

    # wait for the VMs to register with Palette and appear as Edge Hosts
    wait_until_edge_hosts_ready

    # optionally create a two node Cluster Profile using the latest artifact
    # versions - can be skipped by specifying the UID
    if [ -z "${CLUSTER_PROFILE_UID}" ]; then
        prepare_cluster_profile
        create_cluster_profile
    fi

    # create a new Edge Native cluster in Palette using the Edge Hosts
    # provisioned above, plus the two node Cluster Profile
    prepare_master_worker_cluster
    # prepare_master_master_cluster
    create_cluster
}

# This line and the if condition below allow sourcing the script without executing
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
