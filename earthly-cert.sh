#!/bin/sh
# uncomment the line below to enable debug mode
set -x

update-ca-certificates
earthly $@