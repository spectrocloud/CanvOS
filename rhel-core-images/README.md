# Kairos RHEL 8, RHEL 9 and RHEL 10 images

## Build the image using Red Hat Subscription

Follow steps below to execute the build process on the host with access to Red Hat Subscription Management system (redhat.com) and by using Red Hat username and password.

To build the image provide username and password for Red Hat Subscription Manager to register the system and install packages during the build process.

To build RHEL 8 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg USERNAME=<RHSM username> --build-arg PASSWORD='<RHSM password>' -f Dockerfile.rhel8.
```

To build RHEL 9 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg USERNAME=<RHSM username> --build-arg PASSWORD='<RHSM password>' -f Dockerfile.rhel9 .
```

To build RHEL 10 Kairos Image, execute:
```
export RHSM_USERNAME='<RHSM username>'
export RHSM_PASSWORD='<RHSM password>'

docker build -t <local-registry>/<image>:<image-tag> \
  --secret id=RHSM_USERNAME,env=RHSM_USERNAME \
  --secret id=RHSM_PASSWORD,env=RHSM_PASSWORD \
  -f Dockerfile.rhel10 .
```

Unlike the RHEL 8 and RHEL 9 Dockerfiles, RHEL 10 takes the subscription credentials as
BuildKit secrets sourced from environment variables rather than as `--build-arg`. They are
exposed as environment variables only inside the single `RUN` that registers the system, so
they never become build args and never appear in an image layer or in `docker history`. The
build fails immediately with a message naming the missing flag if either secret is absent.

If you prefer keeping credentials in a file instead of the environment, `--secret
id=RHSM_USERNAME,src=<file>` works the same way; `rhel-stig/` uses that variant with a
`rhsm-credentials.yaml`.

### RHEL 10 notes

Base image is `registry.access.redhat.com/ubi10-init:10.2`. The package list differs from RHEL 9 because of upstream changes in RHEL 10:

* `dhclient` was removed — ISC dhcp is no longer shipped in RHEL 10. DHCP is provided by `systemd-networkd`.
* `grub2`, `iptables` and `conntrack` no longer exist as package names. kairos-init requests `grub2` and `iptables` and they resolve through virtual provides (`grub2-pc`, `iptables-nft`), so the explicit list does not repeat them.
* The explicit `dnf install` list is much shorter than the RHEL 8/9 ones — 15 packages instead of 46. kairos-init already installs 128 packages, and a real build showed 34 of the 46 that `Dockerfile.rhel9` lists were reported by dnf as `already installed`. `parted`, `kbd` and `coreutils-single` are kept in the list even though they are redundant today, because they only arrive as transitive dependencies or from the base image and a version bump could drop them silently.
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

Set the CPU model explicitly: QEMU `-cpu host` (or `-cpu max` without KVM), libvirt `host-passthrough`, and for KubeVirt/VMO `spec.template.spec.domain.cpu.model: host-passthrough`. RHEL 8/9 images are unaffected, so "rhel9 boots, rhel10 doesn't" points here rather than at the image.

The build must run on an `x86_64` host. Emulating `linux/amd64` on Apple Silicon does not work for RHEL 10 — its OpenSSL fails its provider integrity self-check under Rosetta, so every HTTPS request (including `dnf makecache`) fails with `error:030000EA:digital envelope routines::provider signature failure`.

**In case of any errors during package installation steps - these errors might be caused by previous build attempts. Execute `docker build` command again by providing argument `--no-cache` to build the image from scratch**

## Build the image using Red Hat Satellite and mirrored repositories

This scenario is for the environment where Red Hat Satellite must be used and access to public Red Hat repositories is not possible. For this case use Dockerfiles `Dockerfile.rhel9.sat` and `Dockerfile.rhel8.sat` - these files are modified to use Red Hat Satellite Activation key to register host and install all required packages.

### Prerequisites

1. Mirror base RHEL UBI image (`registry.access.redhat.com/ubi9-init:9.4-6`) to the internal Container registry. Provide image path for the build process by using argument `BASE_IMAGE`. 

2. Mirror Kairos framework image (`quay.io/kairos/framework:v2.11.7`) to the internal Container registry. Provide image path for the build process by using argument `KAIROS_FRAMEWORK_IMAGE`. 

3. Have the following repositories synced and available on Red Hat Satellite:

For RHEL9:
* rhel-9-for-x86_64-appstream-rpms
* rhel-9-for-x86_64-baseos-rpms
* EPEL9 (upstream URL https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/)

For RHEL8:
* rhel-8-for-x86_64-appstream-rpms
* rhel-8-for-x86_64-baseos-rpms
* EPEL8 (upstream URL https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/)

For RHEL10:
* rhel-10-for-x86_64-appstream-rpms
* rhel-10-for-x86_64-baseos-rpms
* EPEL10 (upstream URL https://dl.fedoraproject.org/pub/epel/10/Everything/x86_64/) — **mandatory** for RHEL 10, not optional: `systemd-networkd`, `systemd-timesyncd`, `livecd-tools` and `haveged` are not in RHEL 10 BaseOS/AppStream, so a Satellite without EPEL 10 fails in the package install step.


4. Create Activation Key in RH Satellite and add corresponding repositories listed above. Make these repositories enabled by default (set `Override Enabled` for these repositories in the Activation Key configuration). Provide Activation Key for the build process by using argument `KEYNAME`.

### Build the image

After all prerequisites completed, ensure all required build arguments are in place:

BASE_IMAGE - path to RHEL8/9 UBI image, for example `redhat.spectrocloud.dev/ubi9-init:9.4-6`

KAIROS_FRAMEWORK_IMAGE - path to Kairos framework image, for example `quay.spectrocloud.dev/kairos/framework:v2.7.33`

SATHOSTNAME - Red Hat Satellite hostname, for example `katello.spectrocloud.dev`

ORGNAME - Organization name in Red Hat Satellite, for example `test-org`

KEYNAME - Name of the Activation key with repositories attached, for example `rhel9-canvos-key`

To build RHEL 8 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg BASE_IMAGE=<base image path> --build-arg KAIROS_FRAMEWORK_IMAGE='<Kairos Framework Path>' --build-arg SATHOSTNAME=<Satellite hostname>  --build-arg ORGNAME=<Satellite Org Name> --build-arg KEYNAME=<Activation key name> -f Dockerfile.rhel8.sat .
```

To build RHEL 9 Kairos Image, execute:
```
docker build -t <local-registry>/<image>:<image-tag> --build-arg BASE_IMAGE=<base image path> --build-arg KAIROS_FRAMEWORK_IMAGE='<Kairos Framework Path>' --build-arg SATHOSTNAME=<Satellite hostname>  --build-arg ORGNAME=<Satellite Org Name> --build-arg KEYNAME=<Activation key name> -f Dockerfile.rhel9.sat .
```

For example, to build RHEL9 image:
```
docker build -t localhost/palette-rhel9:latest --build-arg BASE_IMAGE=redhat.spectrocloud.dev/ubi9-init:9.4-6 --build-arg KAIROS_FRAMEWORK_IMAGE=quay.spectrocloud.dev/kairos/framework:v2.7.33 --build-arg SATHOSTNAME=katello.spectrocloud.dev  --build-arg ORGNAME=test-org --build-arg KEYNAME=rhel9-canvos-key -f Dockerfile.rhel9.sat .
```

For example, to build RHEL8 image:
```
docker build -t localhost/palette-rhel8:latest --build-arg BASE_IMAGE=redhat.spectrocloud.dev/ubi8/ubi-init:8.7-10 --build-arg KAIROS_FRAMEWORK_IMAGE=quay.spectrocloud.dev/kairos/framework:v2.7.33 --build-arg SATHOSTNAME=katello.spectrocloud.dev  --build-arg ORGNAME=test-org --build-arg KEYNAME=rhel8-canvos-key -f Dockerfile.rhel8.sat .
```

To build RHEL 10 Kairos Image via Satellite, execute:
```
export SAT_ACTIVATION_KEY='<Activation key name>'

docker build -t <local-registry>/<image>:<image-tag> \
  --secret id=SAT_ACTIVATION_KEY,env=SAT_ACTIVATION_KEY \
  --build-arg ORGNAME=<Satellite Org Name> \
  --build-arg SATHOSTNAME=<Satellite hostname> \
  --build-arg BASE_IMAGE=<mirrored ubi10-init path> \
  -f Dockerfile.rhel10.sat .
```

`Dockerfile.rhel10.sat` differs from the RHEL 8/9 Satellite files in three ways, all forced by RHEL 10:

* **The activation key is a BuildKit secret, not a `--build-arg`.** An activation key is a credential; passing it as a build arg puts it in `docker history`. `ORGNAME` and `SATHOSTNAME` are not secret and remain build args. This matches `Dockerfile.rhel10`.
* **No `subscription-manager attach --auto`** — the `attach` module was removed in RHEL 10.
* **No `KAIROS_FRAMEWORK_IMAGE`** — the RHEL 10 files use `kairos-init` (`KAIROS_INIT_IMAGE`), not the older framework image. Mirror `quay.io/kairos/kairos-init:v0.16.1` instead and pass it via `--build-arg KAIROS_INIT_IMAGE=`.

It also mirrors `Dockerfile.rhel10` rather than `Dockerfile.rhel9.sat`, so `kairos-init` runs *before* the extra package install — that is the ordering verified end to end on RHEL 10. The resulting package set is identical either way.




> **Note:** a Red Hat Satellite variant for RHEL 10 (`Dockerfile.rhel10.sat`) has not been added yet. Only the direct-subscription `Dockerfile.rhel10` exists.
