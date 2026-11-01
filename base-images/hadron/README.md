# Kairos Hadron base images

Builds the Spectro Kairos base images on top of upstream
[Hadron](https://github.com/kairos-io/hadron), plus the Spectro modules image
they consume. Everything is driven by `base-images/docker-bake.hcl`.

| Target           | What it builds                                                                 |
| ---------------- | ------------------------------------------------------------------------------ |
| `hadron-modules` | Spectro modules layer: DRBD (kernel-coupled), rsyslog, logrotate, iproute2, jq, open-vm-tools, qemu-guest-agent |
| `hadron-std`     | Kairos on `ghcr.io/kairos-io/hadron`                                           |
| `hadron-fips`    | Kairos on `ghcr.io/kairos-io/hadron-fips` (kairos-init `--fips`)              |
| `hadron-uki`     | Kairos on `ghcr.io/kairos-io/hadron-trusted` (Trusted Boot)                   |
| `hadron-fips-uki`| Kairos on `ghcr.io/kairos-io/hadron-fips-trusted` (FIPS + Trusted Boot; Hadron v0.5.3+) |
| `hadron`         | all four variants                                                              |
| `public-hadron`  | group: the four variants plus `hadron-modules` (pushes the modules image too)  |

## Build

Run from `base-images/`. Hadron targets need `hadron/modules.json` as a second
bake file (see [Kernel modules](#kernel-modules-modulesjson)):

```bash
cd base-images

# preview the resolved config (no build)
docker buildx bake -f docker-bake.hcl -f hadron/modules.json --print hadron-std

# build one variant into the local docker image store
docker buildx bake --allow=fs.read=.. -f docker-bake.hcl -f hadron/modules.json hadron-std --load

# build and push all four variants (add hadron-modules, or use public-hadron, to push the modules image too)
docker buildx bake --allow=fs.read=.. -f docker-bake.hcl -f hadron/modules.json hadron --push
```

Instead of repeating `-f`, set the file list once per shell (or in CI):

```bash
export BUILDX_BAKE_FILE=docker-bake.hcl:hadron/modules.json
docker buildx bake --allow=fs.read=.. hadron-uki --push
```

`--allow=fs.read=..` is needed because the shared eMudhra distrust script is
read from `../scripts`.

`hadron-modules` does not need to be built or pushed first: every Hadron
variant builds it in the same bake run and uses it directly (the `contexts`
entry on the `hadron` target), instead of pulling it from the registry.

## Variables

Set as environment variables (e.g. `HADRON_VERSION=v0.5.3 docker buildx bake …`).

| Variable            | Default                                          | Meaning                                                                    |
| ------------------- | ------------------------------------------------ | -------------------------------------------------------------------------- |
| `HADRON_VERSION`    | `v0.5.3`                                         | Upstream Hadron release; must have an entry in `modules.json`              |
| `ARCH`              | `amd64`                                          | Target architecture (`amd64` or `arm64`); one image per arch               |
| `KAIROS_VERSION`    | `v4.4.0`                                         | Kairos release; also the kairos-init image tag                             |
| `KAIROS_INIT_IMAGE` | `quay.io/kairos/kairos-init:${KAIROS_VERSION}`   | Override only to use a mirror                                              |
| `MODEL`             | `generic`                                        | Passed to kairos-init `-m` and used in the tag                             |
| `REGISTRY`          | `us-east1-docker.pkg.dev/spectro-images/edge/base` | Registry prefix for all tags (dev; production is a manual promotion)     |

## Tags

Images are single-architecture; build each arch separately (`ARCH=arm64` on an
arm64 builder avoids emulating the modules compile).

```
<REGISTRY>/kairos-hadron:<HADRON_VERSION>-core-<ARCH>-<MODEL>-<KAIROS_VERSION>[-fips][-uki]
<REGISTRY>/hadron-modules:<HADRON_VERSION>-<ARCH>
```

For example `kairos-hadron:v0.5.3-core-amd64-generic-v4.4.0-fips-uki` and
`hadron-modules:v0.5.3-amd64`.

## Kernel modules (`modules.json`)

Some modules in the modules image are built for one specific Hadron kernel.
DRBD is the one today: a DRBD layer built for a different kernel adds a second
`/usr/lib/modules/<kernel>` tree, dracut picks it, and the build fails later
with a missing `overlayfs` module. So each Hadron release is pinned to the
exact module layer built for its kernel:

```json
{
  "HADRON_RELEASES": [
    {
      "version": "v0.5.1",
      "modules": [
        {
          "name": "drbd",
          "version": "v9.3.3",
          "digest": "sha256:af4ca4349b08a3a23a734455f2901bdac0568701e9442bab93a0a8dbd41e3223"
        }
      ]
    }
  ]
}
```

- `version`: the Hadron release (`HADRON_VERSION`).
- `modules[].name`: the layer, pulled as `ghcr.io/kairos-io/hadron-layers/<name>@<digest>`.
- `modules[].version`: the module version, for humans only.
- `modules[].digest`: what is actually pulled. Always a digest, never a tag:
  upstream re-pushes module tags when its toolchain moves (`drbd:9.3.3` was
  rebuilt for a newer kernel), so a tag can silently point at a build for the
  wrong kernel.

The file is JSON (not YAML) because bake reads JSON bake files natively; the
single top-level `HADRON_RELEASES` key becomes a bake variable.

### Adding a Hadron release

1. Find the module layer built against `hadron-toolchain:<release>`: check the
   layer's OCI labels in the GHCR package versions, and use the multi-arch index
   digest.
2. Add an entry to `HADRON_RELEASES` with that digest.
3. Build with `HADRON_VERSION=<release>`.

A release that is not listed (or a build without `-f hadron/modules.json`)
resolves `DRBD_LAYER` to `MISSING:drbd-for-hadron-<version>-not-in-hadron/modules.json`,
so the Hadron build fails at that `FROM` with the reason in the error. Other
targets in the same bake file are unaffected.

## Files

| File                 | Purpose                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| `Dockerfile`         | Hadron base + modules image + kairos-init, per variant                  |
| `Dockerfile.modules` | Spectro modules image (sources pinned by SHA-256; DRBD from `DRBD_LAYER`) |
| `modules.json`       | Hadron release → kernel module layer map                                |
| `overlay/`           | Service units and config shipped by the modules image                   |
| `patches/`           | Source patches applied when building the modules                        |
