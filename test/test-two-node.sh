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
#      WARNING: govc must be v0.32.0 or greater!
#    - jq (https://jqlang.github.io/jq/download/)
#    - mkisofs (https://command-not-found.com/mkisofs)
#
# 2. Clone CanvOS and checkout this branch.
#
# 3. Configure your Earthly argument file by running: cp .arg.template .arg
#    No modifications to the template are required.
#
# 4. Create a .netrc file in the stylus repo root with GitHub
#    credentials capable of cloning Spectro Cloud internal repos.
#
# 5. Copy the test/env.example file to test/.env and edit test/.env
#    as required.
#
# 6. Source and execute this script:
#
#    source ./test/test-two-node.sh
#    ./test/test-two-node.sh

# Do not edit anything below

declare -a edge_host_names
declare -a vm_array

function init_globals() {
    if [ -n "$SUFFIX_OVERRIDE" ]; then
        export HOST_SUFFIX=$HOST_SUFFIX-$SUFFIX_OVERRIDE
        export CLUSTER_NAME=$CLUSTER_NAME-$SUFFIX_OVERRIDE
    fi

    vm_array+=("tn1-$HOST_SUFFIX" "tn2-$HOST_SUFFIX")
    export HOST_1="${vm_array[0]}"
    export HOST_2="${vm_array[1]}"
    echo "VM names: $HOST_1, $HOST_2"

    if [ -n "$REPLACEMENT_HOST" ]; then
        export HOST_3="tn3-$HOST_SUFFIX"
        vm_array+=($HOST_3)
        echo "Added replacement VM: $HOST_3"
    fi
}

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
UPDATE_KERNEL=false
EOF
}

function create_userdata() {
    cat <<EOF > build/user-data
#cloud-config
stylus:
  debug: true
  users:
  - name: kairos
    passwd: kairos
  site:
    edgeHostToken: "$EDGE_REGISTRATION_TOKEN"
    paletteEndpoint: "$DOMAIN"
EOF
    if [ -n "$PROXY" ]; then
        cat <<EOF >> build/user-data
    network:
      httpProxy: http://10.10.180.0:3128
      httpsProxy: http://10.10.180.0:3128
      noProxy: 10.10.128.10,.spectrocloud.dev,10.0.0.0/8
EOF
    fi
    cat <<EOF >> build/user-data
install:
  poweroff: true
EOF
    if [ -n "$WIFI_NETWORK" ]; then
        cat <<'EOF' >> build/user-data
  bind_mounts:
  - /var/lib/wpa
stages:
  initramfs:
  - users:
      kairos:
        groups:
        - sudo
        passwd: kairos
  network.before:
  - name: "Connect to Wi-Fi"
    commands:
    - |
      # Find the first wireless network interface
      wireless_interface=""
      for interface in $(ip link | grep -oP '^\d+: \K[^:]+(?=:)')
      do
        if [ -d "/sys/class/net/$interface/wireless" ]; then
          wireless_interface=$interface
          break
        fi
      done
      # Check if a wireless interface was found and connect it to WiFi
      if [ -n "$wireless_interface" ]; then
        wpa_passphrase <WIFI_NETWORK> <WIFI_PASSWORD> | tee /var/lib/wpa/wpa_supplicant.conf
        wpa_supplicant -B -c /var/lib/wpa/wpa_supplicant.conf -i $wireless_interface
        dhclient $wireless_interface
      else
        echo "No wireless network interface found."
      fi
EOF
    sed -i "s|<WIFI_NETWORK>|$WIFI_NETWORK|g" build/user-data
    sed -i "s|<WIFI_PASSWORD>|$WIFI_PASSWORD|g" build/user-data
    fi
    echo "created build/user-data"
}

function create_iso() {
    touch meta-data
    mkisofs -output build/user-data.iso -volid cidata -joliet -rock $1 meta-data
    rm -f meta-data
}

function create_userdata_iso() {
    echo Creating user-data ISO...
    create_userdata
    create_iso build/user-data
}

function upload_userdata_iso() {
    echo Uploading user-data ISO...
    govc datastore.upload --ds=$GOVC_DATASTORE --dc=$GOVC_DATACENTER "build/user-data.iso" "${ISO_FOLDER}/user-data.iso"
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
        govc device.cdrom.insert -vm=$vm -device=$dev "${ISO_FOLDER}/user-data.iso"
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
        echo "Power state for ${vm_array[0]}: $powerState1"
        echo "Power state for ${vm_array[1]}: $powerState2"
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

function get_ready_edge_hosts() {
    curl -s -X POST https://$DOMAIN/v1/dashboard/edgehosts/search \
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
        '
}

function wait_until_edge_hosts_ready() {
    echo Waiting for both Edge Hosts to register and become healthy...
    while true; do
        set +e
        ready=$(get_ready_edge_hosts | jq -e 'select(.items != []).items | map(. | select(.status.health.state == "healthy")) | length')
        set -e
        if [ -z ${ready} ]; then
            ready=0
        fi
        if [ $ready -ge 2 ]; then
            echo Both Edge Hosts are healthy!
            break
        fi
        echo "Only $ready/2 Edge Hosts are healthy, sleeping for 5s..."
        sleep 5
    done
}

function ready_edge_host_names() {
    readarray -t edge_host_names < <(get_ready_edge_hosts | jq -r 'select(.items != []).items | map(.metadata.name) | flatten[]')
    export EDGE_HOST_1=${edge_host_names[0]}
    export EDGE_HOST_2=${edge_host_names[1]}
    echo "Ready Edge Host names: ${edge_host_names[@]}"
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
        echo "Deleted Edge Host $host"
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
      .spec.template.packs[1].version = env.K3S_VERSION |
      .spec.template.packs[1].tag = env.K3S_VERSION |
      .spec.template.packs[1].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[2].registry.metadata.uid = env.PUBLIC_PACK_REPO_UID |
      .spec.template.packs[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.template.packs[0].values |= gsub("PE_VERSION"; env.PE_VERSION) |
      .spec.template.packs[0].values |= gsub("K3S_VERSION"; env.K3S_VERSION) |
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
    clusterProfileUid=$1
    curl -s -X DELETE https://$DOMAIN/v1/clusterprofiles/$clusterProfileUid \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID"
    echo "Cluster Profile $clusterProfileUid deleted"
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
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].hostName = env.EDGE_HOST_1 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].hostUid = env.EDGE_HOST_1 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[0].nicName = env.NIC_NAME |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[1].hostName = env.EDGE_HOST_2 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[1].hostUid = env.EDGE_HOST_2 |
      .spec.machinePoolConfig[0].cloudConfig.edgeHosts[1].nicName = env.NIC_NAME |
      .spec.profiles[0].uid = env.CLUSTER_PROFILE_UID |
      .spec.profiles[0].packValues[0].values |= gsub("OCI_REGISTRY"; env.OCI_REGISTRY) |
      .spec.profiles[0].packValues[0].values |= gsub("PE_VERSION"; env.PE_VERSION) |
      .spec.profiles[0].packValues[0].values |= gsub("K3S_VERSION"; env.K3S_VERSION) |
      .spec.profiles[0].packValues[0].values |= gsub("STYLUS_HASH"; env.STYLUS_HASH) |
      .spec.profiles[0].packValues[1].tag = env.K3S_VERSION
    ' test/templates/two-node-master-master.json.tmpl > two-node-create.json
}

function create_cluster() {
    uid=$(curl -s -X POST https://$DOMAIN/v1/spectroclusters/edge-native?ProjectUid=$PROJECT_UID \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d @two-node-create.json | jq -r .uid)
    if [ "$uid" = "null" ]; then
        echo "Cluster creation failed. Please check two-node-create.json and retry creation manually to see Hubble's response."
        return 1
    else
        rm -f two-node-create.json
        echo "Cluster $uid created"
    fi
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

function prepare_cluster_update() {
    export leaderIp=$1
    export replacementHostIp=$2
    jq '
      .cloudConfig.edgeHosts[0].hostAddress = env.leaderIp |
      .cloudConfig.edgeHosts[0].hostName = env.HOST_1 |
      .cloudConfig.edgeHosts[0].hostUid = env.HOST_1 |
      .cloudConfig.edgeHosts[1].hostAddress = env.replacementHostIp |
      .cloudConfig.edgeHosts[1].hostName = env.HOST_3 |
      .cloudConfig.edgeHosts[1].hostUid = env.HOST_3
    ' test/templates/two-node-update.json.tmpl > two-node-update.json
}

function update_cluster() {
    cloudConfigUid=$1
    curl -X PUT https://$DOMAIN/v1/cloudconfigs/edge-native/$cloudConfigUid/machinePools/master-pool \
        -H "ApiKey: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "ProjectUid: $PROJECT_UID" \
        -d @two-node-update.json
    rm -f two-node-update.json
    echo "Cloud config $cloudConfigUid updated"
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
    docker push ${OCI_REGISTRY}/ubuntu:k3s-${K3S_VERSION}-v${PE_VERSION}-${STYLUS_HASH}
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
        grep -q ${OCI_REGISTRY}/ubuntu:k3s-${K3S_VERSION}-v${PE_VERSION}-${STYLUS_HASH}
    ) || ( build_canvos )
}

function clean_all() {
    docker images | grep $OCI_REGISTRY | awk '{print $3;}' | xargs docker rmi --force
    docker images | grep palette-installer | awk '{print $3;}' | xargs docker rmi --force
    earthly prune --reset
    docker system prune --all --volumes --force
}

function main() {
    init_globals

    # build all required edge artifacts
    build_all

    # upload installer ISO to vSphere
    upload_stylus_iso

    # create & upload user-data ISOs, configured to enable two node mode
    create_userdata_iso
    upload_userdata_iso

    # create VMs in vSphere, wait for the installation phase to complete,
    # then power them off, remove the installer ISO, and reboot them
    create_vms
    wait_for_vms_to_power_off
    reboot_vms

    # wait for the VMs to register with Palette and appear as Edge Hosts
    wait_until_edge_hosts_ready
    ready_edge_host_names

    # optionally create a two node Cluster Profile using the latest artifact
    # versions - can be skipped by specifying the UID
    if [ -z "${CLUSTER_PROFILE_UID}" ]; then
        prepare_cluster_profile
        create_cluster_profile
    fi

    # create a new Edge Native cluster in Palette using the Edge Hosts
    # provisioned above, plus the two node Cluster Profile
    prepare_master_master_cluster
    create_cluster
}

# This line and the if condition below allow sourcing the script without executing
# the main function
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced == 1 ]]; then
    script=${BASH_SOURCE[0]}
    if [ -z "$script" ]; then
        script=$0
    fi
    set +e
    echo "You can now use any of these functions:"
    echo ""
    grep ^function $script | grep -v main | awk '{gsub(/function /,""); gsub(/\(\) \{/,""); print;}'
    echo
else
    envfile=$(dirname "${0}")/.env
    if [ -f "${envfile}" ]; then
        source "${envfile}"
        echo "Sourced $envfile"
    else
        echo "Please create a .env file in the test directory and populate it with the required variables."
        exit 1
    fi
    main
fi
