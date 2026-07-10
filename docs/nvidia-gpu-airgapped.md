# Pre-installing the NVIDIA GPU driver for air-gapped GPU Operator

This guide explains how to bake the NVIDIA data-center GPU driver and its
kernel modules **into a CanvOS Ubuntu base image**, so that GPU nodes can run
the [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-air-gapped.html)
in a **fully air-gapped** environment — with **no host-side network access** and
**without the operator's driver container**.

- Script: [`scripts/install-nvidia-drivers.sh`](../scripts/install-nvidia-drivers.sh)
- Wired into the `base-image` target in the [`Earthfile`](../Earthfile),
  gated by `INSTALL_NVIDIA_GPU_DRIVERS=true`.

---

## Why do this (the split of responsibilities)

The GPU Operator normally deploys the NVIDIA driver as a **driver container** that
downloads and compiles the driver at runtime. That requires network access on the
node and a matching kernel-headers source — neither of which exists on an
air-gapped, immutable (Kairos) edge host.

The supported alternative is the **pre-installed driver** model:

| Component | Where it lives | Who installs it |
| --- | --- | --- |
| NVIDIA kernel driver + modules (`nvidia`, `nvidia_uvm`, `nvidia_modeset`, `nvidia_drm`) | **In the OS image** | **This script (build time)** |
| `nvidia-smi` / driver user-space | **In the OS image** | **This script (build time)** |
| nvidia-container-toolkit / runtime class | Container image | GPU Operator (from your content bundle) |
| device-plugin, gpu-feature-discovery, DCGM exporter, MIG manager, validator | Container images | GPU Operator (from your content bundle) |

So: **the OS carries only the driver + kernel modules**; everything else is a
container image you mirror into your Palette content bundle. At boot the node has a
working driver with zero connectivity, and once your bundled operator images are
present the GPU cluster comes up with no external pulls.

At Helm-install time you **must** tell the operator the driver is pre-installed:

```
--set driver.enabled=false
```

If you also opt in to pre-installing the container toolkit on the host
(`NVIDIA_INSTALL_CONTAINER_TOOLKIT=true`, off by default), additionally set:

```
--set toolkit.enabled=false
```

---

## The key build-time problem this solves

Inside the Earthly/Docker build, `uname -r` is the **builder host's** kernel, **not**
the kernel baked into the image. If DKMS builds "for the running kernel", you get
modules for the wrong ABI (or the build fails). The script therefore:

1. derives the **target kernel** from `/lib/modules/*` (the kernel that will boot),
2. installs **ABI-exact kernel headers** for it (reusing
   [`install-kernel-headers.sh`](../scripts/install-kernel-headers.sh), which falls
   back to `snapshot.ubuntu.com` when Ubuntu rotates the ABI out of the live mirror),
3. forces **DKMS build + install + `depmod`** against that target kernel, and
4. **verifies** the resulting `nvidia*.ko` modules actually landed under
   `/lib/modules/<image-kernel>/` — failing the build loudly if they did not.

It runs in the `base-image` target **after** the kernel is finalized
(hold/upgrade/purge/dracut), so modules are always built against the settled kernel.

> **Connectivity note:** the build runs where the builder has internet and bakes
> everything into the image. The resulting image needs no network at boot.

---

## Quick start

1. Edit `.arg` (copied from `.arg.template`) and enable the feature:

   ```sh
   OS_DISTRIBUTION=ubuntu
   OS_VERSION=22.04
   ARCH=amd64

   INSTALL_NVIDIA_GPU_DRIVERS=true
   NVIDIA_DRIVER_BRANCH=570            # verify the branch exists (see below)
   NVIDIA_DRIVER_TYPE=proprietary      # or: open  (Turing+ only)
   ```

2. Build as usual, e.g.:

   ```sh
   ./earthly.sh +build-all-images --ARCH=amd64
   ```

   or override on the command line without touching `.arg`:

   ```sh
   ./earthly.sh +base-image --ARCH=amd64 \
       --INSTALL_NVIDIA_GPU_DRIVERS=true \
       --NVIDIA_DRIVER_BRANCH=570 \
       --NVIDIA_DRIVER_TYPE=proprietary
   ```

3. Mirror the GPU Operator container images into your Palette content bundle
   (per the NVIDIA air-gapped guide), and install the operator with
   `driver.enabled=false`.

---

## Configuration reference

All variables are optional and have defaults. Set them in `.arg` or pass as
`--VAR=value` on the `earthly.sh` command line.

| Variable | Default | Description |
| --- | --- | --- |
| `INSTALL_NVIDIA_GPU_DRIVERS` | `false` | Master switch. When `true`, the driver + DKMS modules are baked into the Ubuntu base image. |
| `NVIDIA_DRIVER_BRANCH` | `570` | Driver branch to install (e.g. `550`, `570`, `580`). Must be a real `-server` branch — see [Choosing a driver branch](#choosing-a-driver-branch). |
| `NVIDIA_DRIVER_TYPE` | `proprietary` | `proprietary` or `open`. `open` uses the NVIDIA open GPU kernel modules (Turing architecture and newer only). |
| `NVIDIA_USE_CUDA_REPO` | `true` | Add the NVIDIA CUDA network repo at build time. It carries every `-server` branch; recommended. `false` uses only Ubuntu's own repos. |
| `NVIDIA_INSTALL_FABRICMANAGER` | `false` | Set `true` for NVSwitch / HGX systems (installs and enables `nvidia-fabricmanager`). |
| `NVIDIA_INSTALL_CONTAINER_TOOLKIT` | `false` | Set `true` to also pre-install `nvidia-container-toolkit` **on the host**. Then set `toolkit.enabled=false` in the operator. Off by default because the operator ships the toolkit. |
| `NVIDIA_REBUILD_INITRD` | `true` | Rebuild the initrd so the `nouveau` blacklist applies during early boot. |

### Choosing a driver branch

Only certain branches publish the headless `-server` packages. Inside the base
image (or any Ubuntu 22.04 box with the CUDA repo added) you can list them:

```sh
apt-cache search 'nvidia-headless-.*-server'
```

Pick a branch supported by both your GPU generation and the CUDA/toolkit versions
of the operator images you're bundling.

---

## What the script configures on the host

- `/etc/modprobe.d/blacklist-nouveau.conf` — blacklists the `nouveau` driver.
- `/etc/modules-load.d/nvidia.conf` — autoloads `nvidia`, `nvidia_uvm`,
  `nvidia_modeset`, `nvidia_drm` at boot.
- `/etc/modprobe.d/nvidia.conf` — `NVreg_PreserveVideoMemoryAllocations=1`.
- Enables `nvidia-persistenced.service` (recommended for data-center GPUs).
- Runs `depmod -a <kernel>` and rebuilds the initrd for the target kernel.

Verify on a booted node:

```sh
nvidia-smi
lsmod | grep nvidia
```

---

## Limitations / caveats

- **Secure Boot / UKI is not supported by this path.** When `IS_UKI=true`, DKMS
  modules are unsigned and will not load under Secure Boot; that requires MOK
  signing, which this script does **not** implement. Use the standard (non-UKI)
  Ubuntu image for GPU nodes.
- **amd64 / Ubuntu only.** The script targets apt-based Ubuntu images on
  `x86_64` (with a best-effort `sbsa` path for arm64). Non-Ubuntu distributions
  are out of scope.
- **Branch/version alignment is yours to own.** Make sure `NVIDIA_DRIVER_BRANCH`
  matches the GPU hardware and the CUDA/toolkit versions expected by the operator
  images in your bundle.
