#!/bin/bash
#
# This script is intented for testing host registration to Palette Edge hosts.
# see
# https://docs.spectrocloud.com/clusters/edge/edgeforge-workflow/palette-canvos/

CANVOS_VM_VCPU=${CANVOS_VM_VCPU:-4}
CANVOS_VM_DISK=${CANVOS_VM_DISK:-35}
CANVOS_VM_RAM=${CANVOS_VM_RAM:-8192}
CANVOS_VM_OSINFO=${CANVOS_VM_OSINFO:-ubuntujammy}
CANVOS_VM_CDROM=${CANVOS_VM_CDROM:-build/palette-edge-installer.iso}

# for some reason I have not yet found
# CanvOS generated iso don't work with virt-install's own flag
# --cloud-init
function prepare_user_data_iso(){
    touch meta-data
    mkisofs -output site-user-data.iso -volid cidata \
        -joliet -rock $1 meta-data
}

function start_machine(){
    local NAME=$1
    local DISK=$2
    virt-install \
        --osinfo ${CANVOS_VM_OSINFO} \
        --name ${NAME} \
        --cdrom ${DISK} \
        --memory ${CANVOS_VM_RAM} \
        --vcpu ${CANVOS_VM_VCPU} \
        --disk size=${CANVOS_VM_DISK} \
        --disk "site-user-data.iso",device=cdrom \
        --virt-type kvm \
        --import 
}

function main(){
    prepare_user_data_iso $1
    start_machine $2 $3
}

function usage(){
    echo >&2 "usage: $0 [-h|--help] [-n|--name <name>] [-i|--iso <disk-image>] -u|--user-data <user-data>"
    echo >&2 ""
    echo >&2 "OPTIONS:"
    echo >&2 "-n | --name        VM Name"
    echo >&2 "-i | --iso         The iso to use (Default: $CANVOS_VM_CDROM)"
    echo >&2 "-u | --user-data   The site user data to for passing the installer"
    echo >&2 "-h | --help        Show this help"
    exit 1;
}

if [ $# -eq 0 ]; then
    usage
fi

OPTIONS=$(getopt -o hn:u: --long help,name:,user-data: -- "$@" 2>/dev/null || usage)

eval set -- "$OPTIONS"

USER_DATA=""

while true; do
  case "$1" in
    --name|-n)
      VM_NAME="$2"
      shift 2
      ;;
    --user-data|-u )
      USER_DATA="$2"
      shift 2
      ;;
    --iso|-i )
      CANVOS_VM_CDROM="$2"
      shift 2
      ;;
    --help|-h )
      usage
      ;;
    -- )
      shift
      break
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [ -z "$USER_DATA" ]; then
  echo "The --user-data option is mandatory"
  exit 1
fi

# This line and the if condition bellow allow sourcing the script without executing
# the main function
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced == 1 ]]; then
    set +e
    echo "You can now use any of these functions:"
    echo ""
    typeset -F |  cut -d" " -f 3
else
    set -eu
    main "$USER_DATA" "$VM_NAME" "$CANVOS_VM_CDROM"
fi

# vim: ts=4 sw=4 sts=4 et 
