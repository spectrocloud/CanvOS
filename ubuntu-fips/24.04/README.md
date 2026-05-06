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

Remediation output is logged under `/var/log/stig-remediation/`. **`stig-remediate.sh`** installs **`openscap-scanner`** and **`ssg-debderived`** when available. On **24.04**, Ubuntu’s `ssg-debderived` often only ships **22.04** datastreams; the script then downloads **[ComplianceAsCode/content](https://github.com/ComplianceAsCode/content) `scap-security-guide-0.1.78`** (same benchmark as `fix.sh`) and places **`ssg-ubuntu2404-ds.xml`** under **`/tmp/stig-static`**, which is copied to `/var/log/stig-remediation/` (air‑gap: set **`STIG_FETCH_UPSTREAM_SSG=0`** and provide **`/tmp/stig-static/ssg-ubuntu2404-ds.xml`** in the image instead).

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `STIG_FETCH_UPSTREAM_SSG` | `1` | When `1` on 24.04, fetch upstream 2404 DS if apt has no 2404 file. |
| `STIG_SSG_VENDOR_VERSION` | `0.1.78` | ComplianceAsCode release tag (without `v`) for the tarball. |

Use **`ssg-ubuntu2404-ds.xml`** for DISA STIG evaluation on a 24.04 node — it is the stream **`fix.sh`** was generated from.

```bash
XCCDF="/var/log/stig-remediation/ssg-ubuntu2404-ds.xml"
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig \
  --report report.html "$XCCDF"
```

If only **`ssg-ubuntu2204-ds.xml`** is present, **`--profile xccdf_org.ssgproject.content_profile_stig` usually fails**: Ubuntu’s 22.04 datastream from `ssg-debderived` is built from content sets that typically expose **CIS / standard** profiles, **not** the DISA STIG profile. List what is actually in a file with:

```bash
oscap info --profiles /var/log/stig-remediation/ssg-ubuntu2204-ds.xml
```

Use a profile from that list (for example a `cis_level1_*` id) if you must scan against the 22.04 datastream, or **rebuild the image** so **`ssg-ubuntu2404-ds.xml`** is copied (networked build with `STIG_FETCH_UPSTREAM_SSG=1`, or vendor the file under `/tmp/stig-static`).

The **`error : Unknown IO error`** line is a known harmless OpenSCAP message on Ubuntu in some code paths; the important line is **“No profile matching …”**.

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
