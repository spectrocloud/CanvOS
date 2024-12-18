BASE_IMAGE="${1:-ubuntu-focal-fips}"

DOCKER_BUILDKIT=1 docker build . --secret id=pro-attach-config,src=pro-attach-config.yaml -t "BASE_IMAGE"
docker run -v "$PWD"/build:/tmp/auroraboot -v /var/run/docker.sock:/var/run/docker.sock --rm quay.io/kairos/auroraboot --set container_image=docker://"BASE_IMAGE" --set "disable_http_server=true" --set "disable_netboot=true" --set "state_dir=/tmp/auroraboot"
