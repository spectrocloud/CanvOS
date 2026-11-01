# Ubuntu 24.04 Trusted Boot (UKI) base image

Kairos-init Ubuntu Noble image with **AMD/NVIDIA GPU firmware removed by
default**, so the resulting UKI stays under the ~1 GiB UEFI load limit.

Build layout matches other Spectro base images (`hadron/`, `rhel-fips/`,
`ubuntu-fips/`):

1. `kairos-init -s install -t true`
2. Customize: install/enable `qemu-guest-agent`, run `trim-gpu-firmware.sh`
3. `kairos-init -s init -t true`

USB media support (`xhci_pci_renesas` via `99-usb-media.conf`) is added later by
Earthfile `+base-image`, not in this Dockerfile.


| File                   | Role                                            |
| ---------------------- | ----------------------------------------------- |
| `Dockerfile`           | Two-stage kairos-init flow + guest agent + trim |
| `trim-gpu-firmware.sh` | Default AMD/NVIDIA firmware/module removal      |

Built by the `ubuntu-uki-24-04` target in `base-images/docker-bake.hcl`.




## Why trim GPU firmware?

Ubuntu’s `linux-firmware` is still a single large package. UKI embeds the whole
rootfs in the PE `.initrd`, so every unused firmware blob counts against the
UEFI size ceiling. Upstream is splitting the package; until that lands in Noble
we delete the discrete-GPU trees after `kairos-init -s install` and before
`-s init` so dracut never packs them:

- [LP#1958518 — Split linux-firmware into multiple packages](https://bugs.launchpad.net/ubuntu/+source/linux-firmware/+bug/1958518)

Removed by default (`KEEP_GPU_FIRMWARE=false`):


| Path                                                                            | Notes                                                                |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `{/lib,/usr/lib}/firmware/{nvidia,amdgpu}` and `nvidia-*` / `amdgpu-*` siblings | Discrete GPU firmware (roots deduped by `realpath`)                  |
| `/lib/modules/*/kernel/drivers/gpu/drm/{amd,nouveau}`                           | In-tree DRM modules for amdgpu / nouveau; `depmod` re-run per kernel |


**Not removed:** CPU microcode, NIC/storage/wifi firmware, Intel i915, `radeon`
(older pre-GCN AMD), etc.

Policy marker: `/etc/canvos/uki-gpu-firmware-policy`

- Trim path: first line `trimmed`, plus `removed_firmware_paths` / `removed_module_trees`
- Keep path (`KEEP_GPU_FIRMWARE=true`): first line `kept`

> Independent of Earthfile `INSTALL_NVIDIA_GPU_DRIVERS` /
> `INSTALL_AMD_GPU_DRIVERS` (default `false`; air-gapped GPU Operator drivers
> when explicitly enabled — mutually exclusive).



## Build

From `base-images/`:

```bash
docker buildx bake --allow=fs.read=.. ubuntu-uki-24-04 --load            # amd64, local docker
docker buildx bake --allow=fs.read=.. ubuntu-uki-24-04 --push            # push amd64
ARCH=arm64 docker buildx bake --allow=fs.read=.. ubuntu-uki-24-04 --push # push arm64
KEEP_GPU_FIRMWARE=true docker buildx bake --allow=fs.read=.. ubuntu-uki-24-04 --load
```

Bake variables (set as environment variables):

| Variable            | Default                                         | Meaning                                                        |
| ------------------- | ----------------------------------------------- | -------------------------------------------------------------- |
| `ARCH`              | `amd64`                                         | Target architecture (`amd64` or `arm64`)                       |
| `KEEP_GPU_FIRMWARE` | `false`                                         | Keep full GPU firmware (larger UKI)                            |
| `KAIROS_VERSION`    | `v4.4.0`                                        | `kairos-init --version`, kairos-init tag, output tag component |
| `KAIROS_INIT_IMAGE` | `quay.io/kairos/kairos-init:${KAIROS_VERSION}`  | Complete kairos-init image reference (mirrors only)            |
| `MODEL`             | `generic`                                       | Passed to kairos-init `-m` and used in the tag                 |
| `REGISTRY`          | `us-east1-docker.pkg.dev/spectro-images/edge/base` | Tag prefix (dev registry)                                   |

Pass `KEEP_GPU_FIRMWARE` as a variable, not `--set ubuntu-uki-24-04.args.KEEP_GPU_FIRMWARE=…`:
`--set` bypasses the bool normalisation, so a value like `True` would silently trim.

Tag:
`${REGISTRY}/kairos-ubuntu:24.04-core-${ARCH}-${MODEL}-${KAIROS_VERSION}-uki`

A build with `KEEP_GPU_FIRMWARE=true` gets the same tag as the trimmed image, so
pushing it replaces the trimmed one; push it under a different `REGISTRY` if both
are needed.

## Use with CanvOS

In `.arg`:

```sh
OS_DISTRIBUTION=ubuntu
OS_VERSION=24.04
IS_UKI=true
BASE_IMAGE=us-docker.pkg.dev/palette-images/edge/kairos-ubuntu:24.04-core-amd64-generic-v4.4.0-uki
```

Then build the installer as usual (`./earthly.sh +uki-iso`, etc.).

## Need GPU firmware on a node?

1. Rebuild the base with firmware kept:
   ```bash
   KEEP_GPU_FIRMWARE=true REGISTRY=myreg docker buildx bake --allow=fs.read=.. ubuntu-uki-24-04 --push
   ```
2. Or enable Earthfile air-gapped GPU driver install on the trimmed base
  (`INSTALL_NVIDIA_GPU_DRIVERS=true` *or* `INSTALL_AMD_GPU_DRIVERS=true`) —
   mutually exclusive; see `docs/nvidia-gpu-airgapped.md` /
   `docs/amd-gpu-airgapped.md`.
3. Longer term: ship firmware as a signed sysext once LP#1958518 (or an
  equivalent split) is available, matching the [Kairos Trusted Boot firmware
   sysext](https://kairos.io/docs/examples/trusted-boot-firmware-sysext/) pattern.



