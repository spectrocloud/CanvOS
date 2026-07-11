# Pre-installing the AMD Instinct GPU driver for air-gapped GPU Operator

This guide explains how to pre-provision the AMD **amdgpu** kernel-mode driver
**in a CanvOS Ubuntu base image**, so that AMD Instinct GPU nodes can run the
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

## Two driver-source modes (`AMDGPU_DRIVER_SOURCE`)

| Mode | What ships in the image | When to use |
| --- | --- | --- |
| `dkms` (default) | AMD's `amdgpu-dkms` source is DKMS-built against the image kernel and lands under `/lib/modules/<kver>/updates/dkms/`. | Recommended for Instinct/MI silicon. The AMD out-of-tree driver typically carries newer SMU firmware interfaces and per-SKU support ahead of what the in-tree amdgpu has. |
| `inbox` | No AMD apt repo is added; the script only ensures the in-tree `amdgpu` module (shipped in `linux-modules-<kver>`) autoloads. | Fallback when the DKMS build fails against your image kernel — e.g. AMD hasn't yet published a driver release whose source builds against a very new kernel. Requires accepting the in-tree driver's feature set. |

Both modes still require `driver.enable=false` at the Helm layer — the operator
does not build a driver either way. A marker at
`/etc/canvos/amdgpu-driver-source` on the booted node records which mode ran.

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
(`driver.enable=false`): the driver is either DKMS-built into the image at
build time (`AMDGPU_DRIVER_SOURCE=dkms`) or the in-tree amdgpu is used as-is
(`AMDGPU_DRIVER_SOURCE=inbox`). Either way, **no host-side mirror or network is
needed at boot**.

---

## The key build-time problem this solves (dkms mode)

Inside the Earthly/Docker build, `uname -r` is the **builder host's** kernel, not
the kernel baked into the image. In `dkms` mode the script therefore:

1. derives the **target kernel** from `/lib/modules/*`,
2. installs **ABI-exact kernel headers** for it (reusing
   [`install-kernel-headers.sh`](../scripts/install-kernel-headers.sh)) plus
   `linux-modules-extra-<kernel>`,
3. registers the AMD driver apt repo via the release-matched `amdgpu-install`
   package (auto-discovered from `repo.radeon.com/amdgpu-install/<release>/`),
4. installs `amdgpu-dkms` and forces **DKMS build + install + `depmod`** against
   the target kernel, and
5. **verifies** an `amdgpu.ko` landed under
   `/lib/modules/<image-kernel>/updates/dkms/` **and** that `dkms status`
   reports the module as `installed` for that kernel — the in-tree module
   shipped under `kernel/…` is *not* accepted. Failing either check aborts
   the image build with a pointer at `AMDGPU_DRIVER_RELEASE` and the inbox
   fallback.

It runs in the `base-image` target **after** the kernel is finalized.

> **No blacklist needed.** Unlike NVIDIA (where `nouveau` must be blacklisted),
> the DKMS `amdgpu` module replaces the in-tree one via `depmod`'s `updates/`
> override. The script just autoloads `amdgpu`.

In `inbox` mode steps 2–5 are skipped entirely; the script only ensures
`amdgpu` autoloads and rebuilds the initrd.

---

## Quick start

1. Edit `.arg` and enable the feature:

   ```sh
   OS_DISTRIBUTION=ubuntu
   OS_VERSION=22            # or 24 for Ubuntu 24.04
   ARCH=amd64

   INSTALL_AMD_GPU_DRIVERS=true
   AMDGPU_DRIVER_SOURCE=dkms      # or "inbox" — see modes above
   AMDGPU_DRIVER_RELEASE=31.30    # amdgpu-install release marker (dkms mode only)
   ```

2. Build as usual, e.g.:

   ```sh
   ./earthly.sh +build-all-images --ARCH=amd64
   ```

   or override on the command line:

   ```sh
   ./earthly.sh +base-image --ARCH=amd64 \
       --INSTALL_AMD_GPU_DRIVERS=true \
       --AMDGPU_DRIVER_RELEASE=31.30
   ```

   If the `dkms` build fails on your image kernel (see the mapping table
   below), rebuild with `--AMDGPU_DRIVER_SOURCE=inbox` to fall back to the
   in-tree driver instead.

3. Mirror the AMD GPU Operator container images into your Palette content bundle
   and install the operator with `driver.enable=false`.

---

## Configuration reference

| Variable | Default | Description |
| --- | --- | --- |
| `INSTALL_AMD_GPU_DRIVERS` | `false` | Master switch. Enables the AMD pre-install pipeline. |
| `AMDGPU_DRIVER_SOURCE` | `dkms` | `dkms` (build AMD's out-of-tree driver against the image kernel) or `inbox` (skip the AMD repo and use the in-tree amdgpu). See modes above. |
| `AMDGPU_DRIVER_RELEASE` | `31.30` | **`dkms` mode only.** `amdgpu-install` release marker (URL segment under `repo.radeon.com/amdgpu-install/<x>/`, e.g. `31.30`, `31.10`, `30.30.4`). Note this is AMD's *driver-release* identifier, not a ROCm x.y.z version — the two schemes coexist and only a subset of ROCm aliases are published as URL paths. |
| `AMDGPU_REBUILD_INITRD` | `true` | Rebuild the initrd for the image kernel. |

### Choosing a driver release (snapshot, 2026-07-11)

The table below is a **snapshot** as of 2026-07-11 of what
`repo.radeon.com/amdgpu/<release>/ubuntu/dists/{jammy,noble}/…/Packages`
publishes for `amdgpu-dkms`. AMD adds new releases periodically — always
cross-check the authoritative matrix before pinning a value:

- [AMD ROCm on Linux — system requirements](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html) (canonical kernel matrix)
- Repo index: <https://repo.radeon.com/amdgpu-install/> (published release markers)

| `AMDGPU_DRIVER_RELEASE` | `amdgpu-dkms` source | Notes |
| --- | --- | --- |
| `30.30.4` | `6.16.13` | Paired with ROCm 7.2.4. Empirically **does not build against Linux 6.17** despite AMD docs listing it as supported for 24.04.4 HWE. Was CanvOS's default before this fix. |
| `31.10` | `6.18.4` | Newer source; picks up mainline through ~6.18. |
| `31.20` | `6.19.0` | |
| **`31.30` (current default)** | `6.19.4` | Confirmed builds against Linux 6.17 on Ubuntu 22.04 / 24.04. Publishes for jammy, noble, and resolute (25.04). |

**How to pick:** the default `31.30` is fine for anyone on 22.04 or 24.04 in
mid-2026. Bump it only when a newer release is required to match the ROCm
user-space release of the operator images you bundle, or if AMD publishes a
release with fixes for your specific silicon. Check AMD's release notes for the
authoritative ROCm ↔ driver-release pairing; the URL scheme intentionally does
**not** encode ROCm x.y.z in the release marker.

> **Docs vs reality:** AMD's system-requirements page has been observed to list
> kernel support that the shipped driver source doesn't yet build against
> (e.g. 30.30.4 with 6.17 on 24.04). Trust the empirical result: if the build
> fails, bump the release or fall back to `inbox`.

### When the DKMS build fails

The most common cause is a **kernel newer than what the chosen driver release
supports** (e.g. running Linux 6.17 with `AMDGPU_DRIVER_RELEASE=30.30.4`,
whose 6.16.13 source doesn't build against 6.17). The build will fail loudly
with the `make.log` tail and a pointer at this document.

Two ways to unblock:

1. **Bump `AMDGPU_DRIVER_RELEASE`** to a newer marker whose source supports
   your kernel (see the table above). This keeps you on AMD's out-of-tree
   driver.
2. **Rebuild with `AMDGPU_DRIVER_SOURCE=inbox`** if no supported release
   exists yet, or if you're willing to trade the OOT driver's newer
   SMU/per-SKU support for whatever the in-tree amdgpu ships with your kernel.
   Enumeration and compute typically work on established silicon (e.g. MI300
   family) with the in-tree driver; expect the operator to lose the
   `amd.com/gpu.driver-version` node label.

---

## Verify on a booted node

```sh
lsmod | grep amdgpu
dmesg | grep -i amdgpu
ls /sys/class/kfd 2>/dev/null && echo "KFD present"
cat /etc/canvos/amdgpu-driver-source     # which mode ran + release info
# In dkms mode, expect a module under /lib/modules/<kver>/updates/dkms/
find /lib/modules/$(uname -r)/updates -name 'amdgpu.ko*' 2>/dev/null
# If you also bundle ROCm user-space tooling:
# rocminfo ; amd-smi list
```

---

## Building the air-gapped content (which images to bundle)

Pre-installing the driver in the OS removes the **driver-build** images (KMM &
friends). The operator still deploys the rest as containers, so those images —
plus cert-manager and a couple of non-image steps — must be handled.
**Bundling images alone is not sufficient.**

### Images to mirror into your content bundle

| Image | Needed with `driver.enable=false`? |
| --- | --- |
| `rocm/gpu-operator` (controller-manager) | Yes |
| `rocm/gpu-operator-utils` | Yes |
| `rocm/k8s-device-plugin` | Yes |
| `rocm/k8s-device-plugin:labeller-*` (node labeller) | Yes |
| `rocm/device-metrics-exporter` | Yes, if you want metrics |
| `rocm/device-config-manager` | Yes |
| `busybox:1.36` (init container) | Yes |
| `registry.k8s.io/nfd/node-feature-discovery` | Yes — unless the cluster already runs NFD |
| cert-manager (`controller`, `webhook`, `cainjector`, `acmesolver`) | Yes — hard dependency |
| KMM images (operator / webhook / worker / signimage) | **No — skip** |
| `gcr.io/kaniko-project/executor`, `ubuntu:<ver>` (driver build) | **No — skip** |
| `rocm/test-runner` | Optional (testing only) |

Render the exact set from the chart rather than transcribing tags:

```sh
helm template amd-gpu ./gpu-operator-<ver>.tgz -f operator-values.yaml \
  | grep -Eo 'image: *"?[^"]+' | sort -u
```

### Non-image steps

1. **Install cert-manager first** (with its images pulled from your registry) —
   the AMD operator will not start without it.
2. In the `DeviceConfig` CR, set `spec.driver.enable: false`.
3. Override every image (`controllerManager.manager.image`,
   `commonConfig.initContainerImage`, `utilsContainer.image`,
   `devicePlugin.devicePluginImage`, `devicePlugin.nodeLabellerImage`,
   `metricsExporter.image`, `configManager.image`, and the NFD image) to your
   bundle/registry; set `imagePullSecrets` as needed.
4. Ensure GPU nodes are labelled (via NFD or manually):
   `feature.node.kubernetes.io/amd-gpu=true`.

### Palette content bundle

Add the AMD GPU Operator (and cert-manager) as Helm packs in the cluster profile,
then build the content bundle so it includes the rendered images above (minus the
KMM/kaniko/ubuntu build images). Images set only via `values.yaml` may need to be
added to the pack's additional-images list if the bundle builder doesn't
auto-detect them. Verify on a node with `lsmod | grep amdgpu` and by checking the
operator pods reach `Ready`.

## Limitations / caveats

- **Secure Boot / UKI is not supported by this path** (unsigned DKMS modules
  won't load). Use the standard (non-UKI) Ubuntu image for GPU nodes.
- **amd64 / Ubuntu only.**
- **Version alignment is yours to own** — `AMDGPU_DRIVER_RELEASE` must line up
  with the ROCm version of the operator images you bundle.
- **`inbox` mode loses the driver-version node label** — the AMD GPU Operator's
  node-labeller reads `/sys/class/drm/card*/device/driver/module/version`,
  which only exists when the driver was DKMS-installed. Enumeration and
  scheduling still work; driver-version-aware policies won't.
