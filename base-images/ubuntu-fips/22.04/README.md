# Kairos Ubuntu jammy fips

- Create the Ubuntu Pro attach config once (shared by 22.04 and 24.04; git-ignored, never commit it):
  `cp ../pro-attach-config.yaml.template ../pro-attach-config.yaml` and replace `REPLACE_WITH_TOKEN`
  with your token. Or point `UBUNTU_PRO_CONFIG` at a file outside the repo.
- Build from `base-images/` with docker bake:

  ```bash
  cd base-images
  docker buildx bake --allow=fs.read=.. ubuntu-fips-22-04 --load
  ```

- Use the generated base image as input in installer generation with `earthly +iso`

The attach config reaches the build only as a BuildKit secret; it is never part of the build context or an image layer.

### Build options (bake variables, set as environment variables)

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `ENABLE_STIG` | `true` | Run DISA STIG remediation (`fix.sh`). Set to `false` (or `0`) for FIPS-only builds without STIG. |
| `SKIP_STIG_BANNER` | `true` | With STIG enabled, restore stock Ubuntu login banners instead of the USG DoD banner (`/etc/issue`, SSH `Banner`, GDM, `/etc/profile.d/ssh_confirm.sh`). |

Examples: `ENABLE_STIG=false docker buildx bake --allow=fs.read=.. ubuntu-fips-22-04`, `UBUNTU_PRO_CONFIG=$HOME/.config/ubuntu-pro.yaml docker buildx bake --allow=fs.read=.. --allow=fs.read=$HOME/.config ubuntu-fips-22-04`.

Pass these as variables, not `--set ubuntu-fips-22-04.args.ENABLE_STIG=…`: `--set` bypasses the bool-to-`1`/`0` conversion.

**Note:** the build context is the `ubuntu-fips` directory so shared files (e.g. `restore-ubuntu-default-banners.sh`) resolve correctly.

The system is not enabling FIPS by default in kernel space. 

To Install with `fips` you need a cloud-config file similar to this one adding `fips=1` to the boot options:

```yaml
#cloud-config

install:
  # ...
  # Set grub options
  grub_options:
    # additional Kernel option cmdline to apply
    extra_cmdline: "fips=1"
```

Notes:
- The dracut patch is needed as Ubuntu has an older version of systemd
- Most of the Dockerfile configuration are: packages being installed by Ubuntu, and the framework files coming from Kairos containing FIPS-enabled packages
- The LiveCD is not running in fips mode

## Verify FIPS is enabled

After install, you can verify that fips is enabled by running:

```bash
kairos@localhost:~$ cat /proc/sys/crypto/fips_enabled
1
kairos@localhost:~$ uname -a
Linux localhost 5.15.0-153-fips 
```

## Running OpenSCAP scans (post-install)

Remediation output is logged under `/var/log/stig-remediation/` (for example `debug.log`, `summary.log`, and `remediation.log`).

**Ubuntu 22.04 (Jammy) and OpenSCAP:** The official Jammy archive does **not** ship `openscap-scanner`, `scap-security-guide`, or `/usr/bin/oscap` (no matching `Package:` lines in `dists/jammy/universe/.../Packages*`). The STIG build therefore **does not** install OpenSCAP or copy a datastream onto the image. Remediation still runs the bundled `fix.sh` with the same logging layout as other releases. To ship a datastream **in the image** on Jammy, add **`/tmp/stig-static/ssg-ubuntu2204-ds.xml`** (or `*-ds-1.2.xml`) during the Docker build; `stig-remediate.sh` copies it to `/var/log/stig-remediation/` like RHEL’s static STIG layout.
