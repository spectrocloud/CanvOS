# Kairos Ubuntu jammy fips

- Edit `pro-attach-config.yaml` with your token
- Run `bash build.sh [<base image>]`
- Use the generated base image as input in installer generation with `earthly +iso`

### Build options (environment variables)

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `ENABLE_STIG` | `1` | When `1`, run DISA STIG remediation (`fix.sh`). Set to `0` for FIPS-only builds without STIG. |
| `SKIP_STIG_BANNER` | `0` | When `1` (with STIG enabled), restore stock Ubuntu login banners instead of the USG DoD banner (`/etc/issue`, SSH `Banner`, GDM, `/etc/profile.d/ssh_confirm.sh`). |

Examples: `ENABLE_STIG=0 bash build.sh`, `SKIP_STIG_BANNER=1 bash build.sh my-tag`.

**Note:** `build.sh` uses the `ubuntu-fips` directory as the Docker build context so shared files (e.g. `restore-ubuntu-default-banners.sh`) resolve correctly.

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

Remediation output is logged under `/var/log/stig-remediation/` (for example `debug.log`, `summary.log`, and `remediation.log`). During the image build, the STIG datastream from `scap-security-guide` is copied into that directory so you can re-evaluate on a deployed node without hunting for content paths:

```bash
# Filename matches the installed guide (Jammy: ssg-ubuntu2204-ds.xml)
XCCDF="/var/log/stig-remediation/ssg-ubuntu2204-ds.xml"

oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig \
  --report report.html "$XCCDF"
```

OpenSCAP scanner and SCAP Security Guide packages are installed when `ENABLE_STIG=1` so `oscap` is available on the image.
