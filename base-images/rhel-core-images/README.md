# Kairos RHEL 9 and RHEL 10 images

## Build the image using Red Hat Subscription

Follow steps below to execute the build process on the host with access to Red Hat Subscription Management system (redhat.com) and by using Red Hat username and password.

### Build with docker bake (RHEL 9 and 10)

From `base-images/`. The credentials are read from the environment and passed to
the build as BuildKit secrets, never as build args:

```bash
export RHSM_USERNAME='<RHSM username>'
export RHSM_PASSWORD='<RHSM password>'

cd base-images
docker buildx bake --allow=fs.read=.. rhel-9 --load
docker buildx bake --allow=fs.read=.. rhel-10 --load

# both, pushed to REGISTRY
docker buildx bake --allow=fs.read=.. rhel-9 rhel-10 --push
```

Images are tagged `<REGISTRY>/kairos-rhel:<9|10>-core-<ARCH>-<MODEL>-<KAIROS_VERSION>`
(variables in `base-images/docker-bake.hcl`). The build fails immediately,
naming the missing variable, if either credential is unset.

### RHEL 10 notes

Base image is `registry.access.redhat.com/ubi10-init:10.2`. The package list differs from RHEL 9 because of upstream changes in RHEL 10:

* `dhclient` was removed — ISC dhcp is no longer shipped in RHEL 10. DHCP is provided by `systemd-networkd`.
* `grub2`, `iptables` and `conntrack` no longer exist as package names. kairos-init requests `grub2` and `iptables` and they resolve through virtual provides (`grub2-pc`, `iptables-nft`), so the explicit list does not repeat them.
* The explicit `dnf install` list is much shorter than the RHEL 9 one — 15 packages instead of 46. kairos-init already installs 128 packages, and a real build showed 34 of the 46 that `Dockerfile.rhel9` lists were reported by dnf as `already installed`. `parted`, `kbd` and `coreutils-single` are kept in the list even though they are redundant today, because they only arrive as transitive dependencies or from the base image and a version bump could drop them silently.
* `subscription-manager attach --auto` was removed in RHEL 10 — the `attach` module no longer exists, since it is obsolete under Simple Content Access. `Dockerfile.rhel10` therefore only registers; that already leaves `rhel-10-for-x86_64-baseos-rpms` and `-appstream-rpms` enabled.
* EPEL 10 is mandatory, not just convenient: `systemd-networkd`, `systemd-timesyncd`, `livecd-tools` and `haveged` are not in RHEL 10 BaseOS/AppStream.
* NetworkManager is **masked, not uninstalled**. On RHEL 9 `dracut-network` requires `(NetworkManager >= 1.20 or dhclient)`, so `dhclient` satisfies it and NetworkManager can be removed. On RHEL 10 the requirement is an unconditional `NetworkManager >= 1.20`, so removing NetworkManager would also remove `dracut-network` and leave the final initramfs without the `network` module that kairos-init asks for in `/etc/dracut.conf.d/kairos-network.conf`. The mask step therefore runs *after* the "unmask everything" step, which would otherwise undo it.

**RHEL 10 requires an `x86-64-v3` CPU to boot.** Red Hat raised the RHEL 10 baseline from `x86-64-v2` to `x86-64-v3`, so nothing older than roughly Intel Haswell / AMD Excavator (2013+) will run it. The guest's CPU model must expose v3, not just the host's — a v3-capable host still fails if the hypervisor presents an older model.

It surfaces two different ways depending on how far the boot gets:

* **Silent death** — GRUB prints `Loading kernel...` / `Loading initrd...` and then nothing at all, no panic and no kernel log, because the check happens before any console exists. Seen under SeaBIOS with QEMU's default `qemu64` model.
* **glibc abort** — the kernel starts, then:

  ```
  Fatal glibc error: CPU does not support x86-64-v3
  Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00
  ```

  RHEL 10's glibc is compiled for v3 and aborts as PID 1, which panics the kernel. Seen under edk2/UEFI on KubeVirt.

Set the CPU model explicitly: QEMU `-cpu host` (or `-cpu max` without KVM), libvirt `host-passthrough`, and for KubeVirt/VMO `spec.template.spec.domain.cpu.model: host-passthrough`. RHEL 9 images are unaffected, so "rhel9 boots, rhel10 doesn't" points here rather than at the image.

The build must run on an `x86_64` host. Emulating `linux/amd64` on Apple Silicon does not work for RHEL 10 — its OpenSSL fails its provider integrity self-check under Rosetta, so every HTTPS request (including `dnf makecache`) fails with `error:030000EA:digital envelope routines::provider signature failure`.

**In case of any errors during package installation steps - these errors might be caused by previous build attempts. Run the build again with `--no-cache` to build the image from scratch.**

## Build the image using Red Hat Satellite and mirrored repositories

This scenario is for the environment where Red Hat Satellite must be used and access to public Red Hat repositories is not possible. For this case use Dockerfiles `Dockerfile.rhel9.sat` and `Dockerfile.rhel10.sat` - these files are modified to use Red Hat Satellite Activation key to register host and install all required packages.

The Satellite images are the `rhel-9-sat` and `rhel-10-sat`
bake targets (tag suffix `-sat`). See [Build the image](#build-the-image) below.

### Prerequisites

1. Mirror the base RHEL UBI image (`registry.access.redhat.com/ubi9-init:9.4-6` or `ubi10-init:10.2`) to the internal container registry. It is passed to the build as the `BASE_IMAGE` build arg.

2. Mirror the kairos-init image (`quay.io/kairos/kairos-init:<KAIROS_VERSION>`; kairos-init is tagged with the Kairos release) to the internal container registry. It is passed to the build as `KAIROS_INIT_IMAGE`.

3. Have the following repositories synced and available on Red Hat Satellite:

For RHEL9:
* rhel-9-for-x86_64-appstream-rpms
* rhel-9-for-x86_64-baseos-rpms
* EPEL9 (upstream URL https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/)

For RHEL10:
* rhel-10-for-x86_64-appstream-rpms
* rhel-10-for-x86_64-baseos-rpms
* EPEL10 (upstream URL https://dl.fedoraproject.org/pub/epel/10/Everything/x86_64/) — **mandatory** for RHEL 10, not optional: `systemd-networkd`, `systemd-timesyncd`, `livecd-tools` and `haveged` are not in RHEL 10 BaseOS/AppStream, so a Satellite without EPEL 10 fails in the package install step.


4. Create Activation Key in RH Satellite and add corresponding repositories listed above. Make these repositories enabled by default (set `Override Enabled` for these repositories in the Activation Key configuration). The activation key is passed to the build as a BuildKit secret (`SATELLITE_ACTIVATION_KEY` below), never as a build arg.

### Build the image

From `base-images/`, with docker bake (RHEL 9 and 10):

```bash
export SATELLITE_ACTIVATION_KEY='<activation key name>'   # secret
export SAT_ORG='<Satellite organization>'                  # e.g. test-org
export SAT_HOST='<Satellite hostname>'                     # e.g. katello.spectrocloud.dev
export KAIROS_INIT_IMAGE='<mirrored kairos-init image>'    # e.g. quay.spectrocloud.dev/kairos/kairos-init:v4.4.0

cd base-images
docker buildx bake --allow=fs.read=.. rhel-9-sat \
  --set rhel-9-sat.args.BASE_IMAGE=<mirrored ubi9-init image> --load
```

Use `rhel-10-sat` (and a mirrored `ubi10-init` image) for RHEL 10.
`BASE_IMAGE` has no bake variable, so it is set per target with `--set`; without
it the Dockerfile default (the public UBI image) is used.

`Dockerfile.rhel10.sat` differs from the RHEL 9 Satellite file because of RHEL 10:

* **No `subscription-manager attach --auto`** — the `attach` module was removed in RHEL 10.

It also mirrors `Dockerfile.rhel10` rather than `Dockerfile.rhel9.sat`, so `kairos-init` runs *before* the extra package install — that is the ordering verified end to end on RHEL 10. The resulting package set is identical either way.
