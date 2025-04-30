#/bin/bash
set -x
containerImage=$2
docker run -v /var/run/docker.sock:/var/run/docker.sock \
  -v $PWD/$1:/config.yaml \
  --net host \
  --privileged \
  -v $PWD:/aurora --rm quay.io/kairos/auroraboot:v0.6.4 \
  --debug \
  --set "disable_http_server=true" \
  --set "container_image=docker:${containerImage}" \
  --set "disable_netboot=true" \
  --set "disk.raw=true" \
  --set "state_dir=/aurora" \
  --cloud-config /config.yaml