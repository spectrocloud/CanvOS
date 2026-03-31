# Kairos Ubuntu noble (24.04) FIPS + STIG

- Edit `pro-attach-config.yaml` with your token
- Run `bash build.sh [<base image name>]`

### Build options (environment variables)

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `ENABLE_STIG` | `1` | When `1`, run OpenSCAP-generated DISA STIG remediation (`fix.sh`). Set to `0` for FIPS-only image without STIG hardening. |
| `SKIP_STIG_BANNER` | `0` | When `1` (and STIG is enabled), restore stock Ubuntu `/etc/issue`, `/etc/issue.net`, SSH banner, profile.d confirm script, and GDM banner text instead of the USG DoD banner. |

Examples:

```bash
# FIPS + full STIG (default)
bash build.sh

# FIPS only, no STIG remediation
ENABLE_STIG=0 bash build.sh my-fips-base

# STIG without USG login banner (non-US deployments)
SKIP_STIG_BANNER=1 bash build.sh my-fips-stig-nobanner
```

Use the generated base image as input in installer generation with `earthly +iso`.

The system does not enable FIPS by default in kernel space.

To install with `fips`, use a cloud-config snippet similar to:

```yaml
#cloud-config

install:
  grub_options:
    extra_cmdline: "fips=1"
```

## Verify FIPS is enabled

After install:

```bash
kairos@localhost:~$ cat /proc/sys/crypto/fips_enabled
1
kairos@localhost:~$ uname -a
Linux localhost 6.8.x-x-fips ...
```

## Regenerating `fix.sh`

`fix.sh` is generated from SCAP Security Guide (STIG profile) for Ubuntu 24.04, for example:

```bash
oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --fix-type bash \
  --output fix.sh \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml
```
