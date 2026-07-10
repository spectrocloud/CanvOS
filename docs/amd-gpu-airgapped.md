# Pre-installing the AMD Instinct GPU driver for air-gapped GPU Operator

This guide explains how to bake the AMD **amdgpu** kernel-mode driver **into a
CanvOS Ubuntu base image**, so that AMD Instinct GPU nodes can run the
[AMD GPU Operator](https://instinct.docs.amd.com/projects/gpu-operator/en/latest/specialized_networks/airgapped-install.html)
in a **fully air-gapped** environment — with **no host-side network access** and
**without the operator building/managing the driver**.

It is the AMD counterpart of [`nvidia-gpu-airgapped.md`](./nvidia-gpu-airgapped.md)
and follows the same "pre-installed driver" model.

- Script: [`scripts/install-amdgpu-drivers.sh`](../scripts/install-amdgpu-drivers.sh)
- Wired into the `base-image` target in the [`Earthfile`](../Earthfile),
  gated by `INSTALL_AMD_GPU_DRIVERS=true`.

**Supported targets:** Ubuntu **22.04** (jammy) and **24.04** (noble), `amd64`.
The codename is derived from the image at build time.

> **Mutually exclusive with NVIDIA.** A single image supports one GPU vendor.
> Enabling both `INSTALL_AMD_GPU_DRIVERS` and `INSTALL_NVIDIA_GPU_DRIVERS` fails
> the build.

---

## Split of responsibilities

| Component | Where it lives | Who installs it |
| --- | --- | --- |
| amdgpu kernel module (`amdgpu`) + firmware | **In the OS image** | **This script (build time)** |
| ROCm user-space, device-plugin, node-labeller, metrics-exporter | Container images | AMD GPU Operator (from your content bundle) |

The OS carries only the kernel driver; everything else is a container image you
mirror into your Palette content bundle. With `driver.enable=false` the operator
"directly uses inbox or pre-installed AMD GPU drivers" and only deploys the
device-plugin / node-labeller / metrics-exporter.

At Helm-install time you **must** set:

```
--set driver.enable=false        # note: "enable", not "enabled"
```

---

## Relationship to the AMD air-gapped guide

The AMD guide's `driver.enable=true` path has the operator build the out-of-tree
driver at runtime, which needs build packages and (in restricted networks) a
local package mirror. This integration uses the opposite path
(`driver.enable=false`): the `amdgpu-dkms` driver is compiled into the image at
build time, so **no host-side mirror or network is needed at boot**. AMD's host
package requirements (`linux-headers-$(uname -r)`, `linux-modules-extra-...`,
`amdgpu-dkms`) are all satisfied at build time inside the image.

---

## The key build-time problem this solves

Inside the Earthly/Docker build, `uname -r` is the **builder host's** kernel, not
the kernel baked into the image. The script therefore:

1. derives the **target kernel** from `/lib/modules/*`,
2. installs **ABI-exact kernel headers** for it (reusing
   [`install-kernel-headers.sh`](../scripts/install-kernel-headers.sh)) plus
   `linux-modules-extra-<kernel>`,
3. registers the AMD driver apt repo via the version-matched `amdgpu-install`
   package (auto-discovered from `repo.radeon.com/amdgpu-install/<version>/`),
4. installs `amdgpu-dkms` and forces **DKMS build + install + `depmod`** against
   the target kernel, and
5. **verifies** `amdgpu.ko` landed under `/lib/modules/<image-kernel>/`, failing
   the build loudly otherwise.

It runs in the `base-image` target **after** the kernel is finalized.

> **No blacklist needed.** Unlike NVIDIA (where `nouveau` must be blacklisted),
> `amdgpu-dkms` replaces the in-tree `amdgpu` module of the same name; `depmod`
> prefers the DKMS copy. The script just autoloads `amdgpu`.

---

## Quick start

1. Edit `.arg` and enable the feature:

   ```sh
   OS_DISTRIBUTION=ubuntu
   OS_VERSION=22            # or 24 for Ubuntu 24.04
   ARCH=amd64

   INSTALL_AMD_GPU_DRIVERS=true
   AMDGPU_ROCM_VERSION=7.2.4
   ```

2. Build as usual, e.g.:

   ```sh
   ./earthly.sh +build-all-images --ARCH=amd64
   ```

   or override on the command line:

   ```sh
   ./earthly.sh +base-image --ARCH=amd64 \
       --INSTALL_AMD_GPU_DRIVERS=true \
       --AMDGPU_ROCM_VERSION=6.4.4
   ```

3. Mirror the AMD GPU Operator container images into your Palette content bundle
   and install the operator with `driver.enable=false`.

---

## Configuration reference

| Variable | Default | Description |
| --- | --- | --- |
| `INSTALL_AMD_GPU_DRIVERS` | `false` | Master switch. Bakes `amdgpu-dkms` into the Ubuntu base image. |
| `AMDGPU_ROCM_VERSION` | `7.2.4` | ROCm/driver release to install. Selects the `amdgpu-install` package under `repo.radeon.com/amdgpu-install/<version>/`, which configures the matching driver repo. **Must match the ROCm version of the operator images you bundle.** |
| `AMDGPU_REBUILD_INITRD` | `true` | Rebuild the initrd for the image kernel. |

### Choosing a version

Browse available releases at
<https://repo.radeon.com/amdgpu-install/> (e.g. `7.2.4`, `6.4.4`, `6.2.2`). Pick
the one matching your hardware and the operator images in your bundle.

---

## Verify on a booted node

```sh
lsmod | grep amdgpu
dmesg | grep -i amdgpu
ls /sys/class/kfd 2>/dev/null && echo "KFD present"
# If you also bundle ROCm user-space tooling:
# rocminfo ; amd-smi list
```

---

## Limitations / caveats

- **Secure Boot / UKI is not supported by this path** (unsigned DKMS modules
  won't load). Use the standard (non-UKI) Ubuntu image for GPU nodes.
- **amd64 / Ubuntu only.**
- **Version alignment is yours to own** — `AMDGPU_ROCM_VERSION` must line up with
  the ROCm version of the operator images you bundle.
