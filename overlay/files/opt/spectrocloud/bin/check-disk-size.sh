#!/bin/bash

set -e

REQUIRED_FREE_DISK=$1

FREE=$(df -h --output=pcent /var/ | tail -n 1 | tr -d '\% ')

if (( FREE < REQUIRED_FREE_DISK )); then
   echo "Not enough free disk, required: $1. Free: $FREE"
   exit 1
fi

echo "Free disk ok, required: $1. Free: $FREE"
exit 0
