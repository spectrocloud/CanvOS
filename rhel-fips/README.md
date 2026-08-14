# Kairos RHEL8, RHEL9 and RHEL10 FIPS

## Build a RHEL FIPS Image (8, 9 or 10)

One script builds all three versions — pass the RHEL major version and it selects the matching
`Dockerfile.rhel<N>`:

```bash
export RHSM_USERNAME='<RHSM username>'
export RHSM_PASSWORD='<RHSM password>'

bash build.sh --ver 8     # -> rhel8-byoi-fips
bash build.sh --ver 9     # -> rhel9-byoi-fips
bash build.sh --ver 10    # -> rhel10-byoi-fips

# custom name, and push to a registry in one step
bash build.sh --ver 10 --tag <registry>/<image>:<tag> --push
```

| flag | |
|---|---|
| `--ver <8\|9\|10>` | RHEL major version; selects `Dockerfile.rhel<N>` (required) |
| `--tag <image>` | image name to build (default `rhel<N>-byoi-fips`) |
| `--push` | `docker push` the image after a successful build; requires `--tag` |

`--push` refuses to run without `--tag`, since the default name is unqualified and pushing it
would fail or silently target Docker Hub. Log in to the registry (`docker login`) first.

Then use the generated base image as input in installer generation with `earthly +iso`.

**Credentials are exported, not passed as arguments.** The build fails immediately with a message
naming the missing variable if either is unset.

Note the old `build.sh.rhel8` defaulted its image name to `rhel-byoi-fips` (no `8`); the
unified script uses `rhel<N>-byoi-fips` consistently.

### RHEL 10 differences

`Dockerfile.rhel10` diverges from the RHEL 8/9 FIPS files in ways forced by RHEL 10:

* **`dhclient` / `dhcp-client` are gone** — ISC dhcp was removed. DHCP is handled by `systemd-networkd`.
* **NetworkManager is masked, not uninstalled.** On RHEL 10 `dracut-network` requires `NetworkManager >= 1.20` unconditionally (RHEL 9 accepts `dhclient` as an alternative), so removing it would also remove `dracut-network` and leave the initramfs with no network module. The mask step runs *after* the "unmask everything" step, which would otherwise undo it.
* **No `subscription-manager attach --auto`** — the `attach` module was removed in RHEL 10.
* **The package list is much shorter** (15 entries vs ~46). `kairos-init` already installs ~128 packages; on RHEL 10 only these add anything.
* **`overlay/rhel10/` ships no udev rules.** RHEL 10 already provides `60-persistent-storage.rules` (systemd-udev) and `13-dm-disk.rules` (device-mapper), so `dracut.conf`'s `install_items` picks up the distro's own copies instead of stale RHEL 9 ones.
* **An `x86-64-v3` CPU is required to boot RHEL 10** — see `rhel-core-images/README.md` for the two failure signatures. This applies to the FIPS image too.

`dracut.conf` is shared across all three versions and needs no RHEL 10 changes: the `01fips` dracut module is present, and both `install_items` paths exist in the RHEL 10 image.

**Note**: Red Hat subscription credentials are required to build these images as RHEL8/RHEL9/RHEL10 FIPS packages are only available through Red Hat repositories.

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
- Most of the Dockerfile configuration are: packages being installed by RHEL8/RHEL9, and the framework files coming from Kairos containing FIPS-enabled packages
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
