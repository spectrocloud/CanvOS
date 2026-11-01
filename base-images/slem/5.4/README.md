# SUSE Linux Enterprise Micro

Kairos base on `registry.suse.com/suse/sle-micro-rancher/5.4`. No registration
code is needed; any Docker host with BuildKit works.

## Build

From `base-images/`:

```bash
docker buildx bake --allow=fs.read=.. slem-5-4 --load
```

The image is tagged `<REGISTRY>/kairos-slem:5.4-core-<ARCH>-<MODEL>-<KAIROS_VERSION>`
(see the variables in `base-images/docker-bake.hcl`).
