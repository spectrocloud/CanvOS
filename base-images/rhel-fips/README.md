# Kairos RHEL 9 and RHEL 10 FIPS

## Build a RHEL FIPS image

RHEL 9 and 10 are built with docker bake from `base-images/`. Red Hat
subscription credentials are read from the environment and passed to the build
as BuildKit secrets, never as build args:

```bash
export RHSM_USERNAME='<RHSM username>'
export RHSM_PASSWORD='<RHSM password>'

cd base-images
docker buildx bake --allow=fs.read=.. rhel-fips-9 --load
docker buildx bake --allow=fs.read=.. rhel-fips-10 --load

# both, pushed to REGISTRY
docker buildx bake --allow=fs.read=.. rhel-fips-9 rhel-fips-10 --push
```

Images are tagged `<REGISTRY>/kairos-rhel:<9|10>-core-<ARCH>-<MODEL>-<KAIROS_VERSION>-fips`
(variables in `base-images/docker-bake.hcl`). The build fails immediately,
naming the missing variable, if either credential is unset.

Then use the generated base image as input in installer generation with `earthly +iso`.

### RHEL 10 differences

`Dockerfile.rhel10` diverges from the RHEL 9 FIPS file in ways forced by RHEL 10:

* **`dhclient` / `dhcp-client` are gone** — ISC dhcp was removed. DHCP is handled by `systemd-networkd`.
* **NetworkManager is masked, not uninstalled.** On RHEL 10 `dracut-network` requires `NetworkManager >= 1.20` unconditionally (RHEL 9 accepts `dhclient` as an alternative), so removing it would also remove `dracut-network` and leave the initramfs with no network module. The mask step runs *after* the "unmask everything" step, which would otherwise undo it.
* **No `subscription-manager attach --auto`** — the `attach` module was removed in RHEL 10.
* **The package list is much shorter** (15 entries vs ~46). `kairos-init` already installs ~128 packages; on RHEL 10 only these add anything.
* **RHEL 10 uses only `overlay/common/` (no udev rules).** RHEL 10 already provides `60-persistent-storage.rules` (systemd-udev) and `13-dm-disk.rules` (device-mapper), so `dracut.conf`'s `install_items` picks up the distro's own copies instead of stale RHEL 9 ones.
* **An `x86-64-v3` CPU is required to boot RHEL 10** — see `rhel-core-images/README.md` for the two failure signatures. This applies to the FIPS image too.

`dracut.conf` is shared by both versions and needs no RHEL 10 changes: the `01fips` dracut module is present, and both `install_items` paths exist in the RHEL 10 image.

**Note**: Red Hat subscription credentials are required to build these images as RHEL 9/RHEL 10 FIPS packages are only available through Red Hat repositories.

The system is not enabling FIPS by default in kernel space. 

To Install with `fips` you need a cloud-config file similar to this one adding `fips=1` to the boot options:

```yaml
#cloud-config

install:
  # ...
  # Set grub options
  grub_options:
    # additional Kernel option cmdline to apply
    extra_cmdline: "fips=1 selinux=0"
```

Notes:
- Most of the Dockerfile configuration are: packages being installed for RHEL 9/RHEL 10, and the framework files coming from Kairos containing FIPS-enabled packages
- The LiveCD is not running in fips mode
- You must add `selinux=0`. SELinux is not supported yet and must be explicitly disabled
- Red Hat subscription is required for access to FIPS-compliant packages

## Verify FIPS is enabled

After install, you can verify that fips is enabled by running:

```bash
kairos@localhost:~$ cat /proc/sys/crypto/fips_enabled
1
kairos@localhost:~$ uname -a
Linux localhost 5.4.0-1007-fips #8-Ubuntu SMP Wed Jul 29 21:42:48 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux
```
