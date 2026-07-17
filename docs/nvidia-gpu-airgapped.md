# Pre-installing the NVIDIA GPU driver for air-gapped GPU Operator

This guide explains how to bake the NVIDIA data-center GPU driver and its
kernel modules **into a CanvOS Ubuntu base image**, so that GPU nodes can run
the [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-air-gapped.html)
in a **fully air-gapped** environment — with **no host-side network access** and
**without the operator's driver container**.

- Script: [`scripts/install-nvidia-drivers.sh`](../scripts/install-nvidia-drivers.sh)
- Wired into the `base-image` target in the [`Earthfile`](../Earthfile),
  gated by `INSTALL_NVIDIA_GPU_DRIVERS=true`.

**Supported targets:** Ubuntu **22.04** and **24.04**, `amd64`. The script is
version-agnostic — it derives the CUDA repo tag (`ubuntu2204` / `ubuntu2404`) and
the kernel codename (`jammy` / `noble`) from the image's `/etc/os-release` at
build time, so the same script works for both without changes.

> For AMD Instinct GPUs, see [`amd-gpu-airgapped.md`](./amd-gpu-airgapped.md).
> The two are **mutually exclusive** — enabling both `INSTALL_NVIDIA_GPU_DRIVERS`
> and `INSTALL_AMD_GPU_DRIVERS` fails the build.

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

## Relationship to NVIDIA's "Local Package Repository" section

The NVIDIA air-gapped guide lists these Ubuntu packages under
**Local Package Repository → Required Packages**:

```
ubuntu:
   linux-headers-${KERNEL_VERSION}
   linux-image-${KERNEL_VERSION}
   linux-modules-${KERNEL_VERSION}
```

That list belongs to the **driver-container** strategy: the node runs the GPU
Operator's *driver container*, which compiles the driver **at runtime** and pulls
those OS packages from **a local Ubuntu apt mirror you host**. It requires
`driver.enabled=true` plus a maintained mirror.

This CanvOS integration deliberately uses the **other** supported strategy —
**pre-installed driver in the OS image** (`driver.enabled=false`) — so **no local
apt mirror is needed**. The substance of those three packages is still satisfied,
just at build time inside the image rather than from a runtime mirror:

| NVIDIA-required package | How this integration satisfies it |
| --- | --- |
| `linux-headers-${KERNEL_VERSION}` | Installed at build time by `install-kernel-headers.sh` (ABI-exact; DKMS builds against these). |
| `linux-image-${KERNEL_VERSION}` | Already shipped in the Kairos base image (the bootable kernel). |
| `linux-modules-${KERNEL_VERSION}` | Already shipped in the Kairos base image (`/lib/modules/${KERNEL_VERSION}/`). |

If you specifically want the driver-container + local-mirror model instead, this
script is not the right tool — you would host an apt mirror serving the packages
above and leave `driver.enabled=true`.

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
   OS_VERSION=22            # or 24 for Ubuntu 24.04
   ARCH=amd64

   INSTALL_NVIDIA_GPU_DRIVERS=true
   NVIDIA_DRIVER_BRANCH=580            # verify the branch exists (see below)
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
       --NVIDIA_DRIVER_BRANCH=580 \
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
| `NVIDIA_DRIVER_BRANCH` | `580` | Driver **branch** to install (e.g. `550`, `570`, `580`). apt installs the latest patch within the branch — it is not pinned to an exact point release (e.g. `580.159.03`). Must be a real `-server` branch — see [Choosing a driver branch](#choosing-a-driver-branch). |
| `NVIDIA_DRIVER_TYPE` | `open` | `open` or `proprietary`. `open` uses the NVIDIA open GPU kernel modules and is **required** on Hopper (H100/H200) and Blackwell (RTX PRO 6000 Blackwell, B100/B200/GB200); the closed modules fail with `RmInitAdapter (0x22:0x56:897)` on those GPUs. Also safe on Turing/Ampere/Ada. Override to `proprietary` only for pre-Turing hardware (Pascal/Volta). See [Choosing the module flavor](#choosing-the-module-flavor-nvidia_driver_type). |
| `NVIDIA_USE_CUDA_REPO` | `true` | Add the NVIDIA CUDA network repo at build time. It carries every `-server` branch; recommended. `false` uses only Ubuntu's own repos. |
| `NVIDIA_INSTALL_FABRICMANAGER` | `true` | Installs `nvidia-fabricmanager-<branch>` + `libnvidia-nscq-<branch>` and enables the unit — **required** on NVSwitch systems (HGX H100/H200, HGX B200, DGX, GB200 NVL72) for multi-GPU NVLink to come up. On non-NVSwitch hosts the daemon exits early and the unit stays inactive; no kernel side effect, no restart loop, ~60–90 MB image cost. Set `false` to skip if you want to shave the image and know none of your fleet uses NVSwitch. |
| `NVIDIA_INSTALL_IMEX` | `true` | Installs `nvidia-imex-<branch>` (Internode Memory Exchange daemon) and enables the unit — **required** on **GB200 NVL72** for multi-node NVLink Sharp (Blackwell, driver 570+). Not needed for single-node HGX B200 or HGX H100. On non-NVL72 hosts the daemon has no `/etc/nvidia-imex/nodes_config.cfg` and exits cleanly, so the unit stays inactive; ~10–20 MB image cost. Best-effort: older driver branches (pre-570) do not publish the package and the install step is skipped with a warning. |
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

### Choosing the module flavor (`NVIDIA_DRIVER_TYPE`)

The default is `open`. It works on every server GPU generation Turing and newer,
and is **required** for Hopper and Blackwell. Override to `proprietary` only for
pre-Turing hardware.

| GPU generation | Example cards                                          | Required `NVIDIA_DRIVER_TYPE` |
| -------------- | ------------------------------------------------------ | ----------------------------- |
| Blackwell      | RTX PRO 6000 Blackwell, B100, B200, GB200              | `open` (only)                 |
| Hopper         | H100, H200                                             | `open` (only)                 |
| Ada Lovelace   | L4, L40, L40S, RTX 6000 Ada                            | either (`open` recommended)   |
| Ampere         | A100, A10, A30, A40                                    | either                        |
| Turing         | T4, RTX 20xx                                           | either                        |
| Pre-Turing     | V100, P100, P40                                        | `proprietary` (only)          |

Symptom of the wrong choice on Hopper/Blackwell: `nvidia-smi` reports
`No devices were found`, and `dmesg` shows one line per GPU of the form
`NVRM: GPU <bus>: RmInitAdapter failed! (0x22:0x56:897)`. In that state the
GPU Operator's toolkit init container loops on
`Attempting to validate a driver container installation`, containerd never
registers the `nvidia` runtime handler, the device plugin never advertises
`nvidia.com/gpu`, and workload pods stay `Pending` on
`Insufficient nvidia.com/gpu`.

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

## Building the air-gapped content (which images to bundle)

Pre-installing the driver in the OS only removes the **driver image**. The
operator still deploys everything else as containers, so those images (and a few
non-image steps) must be handled. **Bundling images alone is not sufficient.**

### Images to mirror into your content bundle

| Image | Needed with `driver.enabled=false`? |
| --- | --- |
| `gpu-operator` | Yes |
| `gpu-operator-validator` | Yes |
| `container-toolkit` | Yes — **unless** you also pre-installed it on the host (`NVIDIA_INSTALL_CONTAINER_TOOLKIT=true` → then set `toolkit.enabled=false` and skip this image) |
| `k8s-device-plugin` | Yes |
| `gpu-feature-discovery` | Yes |
| `dcgm` + `dcgm-exporter` | Yes, if you want GPU metrics |
| `node-feature-discovery` | Yes — unless the cluster already runs NFD (`nfd.enabled=false`) |
| CUDA validation image (`nvcr.io/nvidia/cuda:…`) | Yes — used by the validator init container (easy to miss) |
| `k8s-mig-manager` | Only if using MIG |
| **`driver`** | **No — skip it (that's the point of pre-installing)** |

Don't transcribe tags by hand — they change per operator version. Render the
exact set from the chart and mirror precisely that:

```sh
helm template gpu-operator nvidia/gpu-operator --version <ver> \
  --set driver.enabled=false | grep -Eo 'image: *"?[^"]+' | sort -u
```

### Non-image steps

1. `--set driver.enabled=false`.
2. Override **every** image `repository` to your bundle/registry and set
   `imagePullSecrets`.
3. **Palette Edge (k3s / rke2) gotcha:** the container-toolkit defaults assume
   stock containerd. On k3s/rke2 you must point it at the right socket and
   config, e.g.:

   ```
   --set toolkit.env[0].name=CONTAINERD_CONFIG \
   --set toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml \
   --set toolkit.env[1].name=CONTAINERD_SOCKET \
   --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock \
   --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
   --set toolkit.env[2].value=nvidia
   ```

   (rke2 paths: `/var/lib/rancher/rke2/agent/etc/containerd/config.toml.tmpl`,
   `/run/k3s/containerd/containerd.sock`.) Miss this and workloads never get the
   GPU runtime even though the driver is present.

### Palette content bundle

Add the GPU Operator as a Helm pack in the cluster profile, then build the
content bundle so it includes the rendered images above (minus `driver`). Images
set only via `values.yaml` may need to be added to the pack's additional-images
list if the bundle builder doesn't auto-detect them. Verify on a node with
`nvidia-smi` and by checking the operator's `*-validator` pods reach `Ready`.

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
