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

The bundled `fix.sh` carries two kinds of **jammy-aligned** changes:

1. **Explicit comments (Kairos / time sync)** — Rules that install **chrony**, remove **systemd-timesyncd**, or edit **chrony.conf** are commented out with `EXCEPTION (CanvOS/Kairos)` notes, matching the intent of `ubuntu-fips/22.04/fix.sh`, so **kairos-init** can keep enabling **systemd-timesyncd**.

2. **Docker build applicability** — Noble’s OpenSCAP script uses `dpkg-query … linux-base`, so remediations run during `docker build`. Jammy’s script used `/.dockerenv` / `/.containerenv` for most rules, so they **did not** run in-container. After regenerating `fix.sh`, run `python3 24.04/align-fix-sh-dockerenv.py` from the repo (or `python3 align-fix-sh-dockerenv.py` inside `ubuntu-fips/24.04`) to remap each rule to the same guard style as 22.04. Rules that had **no** `if` in jammy (e.g. some audit `chown`/`chmod` snippets) still run during the image build, as before.

Regenerating `fix.sh` from **oscap** drops both the comments and the dockerenv alignment — re-apply them or keep a patch.

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

## Running OpenSCAP scans (post-install)

Remediation output is logged under `/var/log/stig-remediation/` (for example `debug.log`, `summary.log`, and `remediation.log`). During the image build, `stig-remediate.sh` installs **`openscap-scanner`** and **`ssg-debderived`** (Ubuntu ships SSG datastreams in that package, not under the binary name `scap-security-guide`) when available, then copies the best-matching **`ssg-ubuntu*-ds.xml`** to that directory.

```bash
# Typical name on 24.04 when 2404 content is present (may be 2204 if only that ship set is in your ssg-debderived)
XCCDF="/var/log/stig-remediation/ssg-ubuntu2404-ds.xml"

oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig \
  --report report.html "$XCCDF"
```

Use `ls /var/log/stig-remediation/ssg-ubuntu*-ds.xml` on the node to use the exact file that was copied.

To **pin** a specific datastream in the image (e.g. match `fix.sh` exactly), place it at **`/tmp/stig-static/ssg-ubuntu2404-ds.xml`** in the Docker build (same idea as `rhel-stig/static/`).

## Regenerating `fix.sh`

`fix.sh` is generated from SCAP Security Guide (STIG profile) for Ubuntu 24.04, for example:

```bash
oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --fix-type bash \
  --output fix.sh \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml
```

Then re-apply **CanvOS** edits: comment the Kairos/chrony/timesyncd blocks (see current `fix.sh`), and run **`align-fix-sh-dockerenv.py`** so image-build behavior matches **22.04**.
