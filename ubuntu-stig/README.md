# Ubuntu 24.04 STIG

This directory contains Dockerfiles and build scripts for creating Ubuntu 24.04 STIG-compliant base images for use with Palette Edge clusters.

## Overview

Ubuntu 24.04 STIG (Security Technical Implementation Guide) compliance is required for regulated and government customers. These images apply DISA STIG security hardening using OpenSCAP and scap-security-guide.

## Build

### Non-FIPS STIG Image

```bash
cd ubuntu-stig
bash build.sh.ubuntu24.04 [<image-name>] [false]
```

Example: `bash build.sh.ubuntu24.04 ubuntu24.04-byoi-stig false`

### FIPS STIG Image

```bash
cd ubuntu-stig
bash build.sh.ubuntu24.04 [<image-name>] true [<ubuntu-pro-token>]
```

Example: `bash build.sh.ubuntu24.04 ubuntu24.04-byoi-stig-fips true $UBUNTU_PRO_TOKEN`

Or use Docker secret: `docker build --secret id=pro-attach-config,src=pro-attach-config.yaml ...`

## Static STIG Content (Reproducible Releases)

To ensure released base images use a **verified, pinned** STIG guide and remediation (avoiding unforeseen changes that could affect Kubernetes clusters), we support static STIG content:

1. **Before a release**, run the update script to download and pin STIG content:
   ```bash
   cd ubuntu-stig
   bash scripts/update-stig-content.sh v0.1.79
   ```
   This downloads the ComplianceAsCode release, builds the Ubuntu 24.04 (or 22.04) datastream, and generates the remediation script into `static/`.

2. **Build with static content**: Ensure `static/` contains `ssg-ubuntu2404-ds.xml` (or `ssg-ubuntu2204-ds.xml`) and `stig-fix.sh` before building. The Dockerfile copies these into the image.

3. **Without static content**: The build falls back to system-installed `scap-security-guide` and generates remediation at build time.

### Using Latest STIG (for customers who want current content)

To build an image with the **latest** STIG guide and remediation instead of the pinned release:

1. **Option A – Omit static content**: Ensure `static/` contains only `VERSION` (remove or do not add `ssg-ubuntu2404-ds.xml` and `stig-fix.sh`). The build will use system-installed `scap-security-guide` and generate remediation at build time.

2. **Option B – Pin a newer version**: Run `scripts/update-stig-content.sh v0.1.XX` with a newer ComplianceAsCode release before building.

**Source**: [ComplianceAsCode/content releases](https://github.com/ComplianceAsCode/content/releases)

## Build Requirements

The update script (`scripts/update-stig-content.sh`) requires build dependencies:

- **Ubuntu 24.04**: `apt install cmake make openscap-utils openscap-scanner python3 python3-pip libxml2-utils xsltproc`

Check latest STIG version: `curl -s https://api.github.com/repos/ComplianceAsCode/content/releases/latest | jq -r '.tag_name'`

## Running OpenSCAP Scans (Post-Install)

To run a scan on a deployed node:

```bash
# The ds xml is copied to the stig-remediation log dir during build (e.g. ssg-ubuntu2404-ds.xml)
XCCDF="/var/log/stig-remediation/ssg-ubuntu2404-ds.xml"

oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig \
  --report report.html "$XCCDF"
```

### Known OpenSCAP Errors on Ubuntu

You may see these non-fatal errors; the scan still completes and produces results:

- **"Unknown IO error" / "cpelang_priv.c"** – OpenSCAP's CPE (Common Platform Enumeration) code tries to read RPM files; Ubuntu is Debian-based and has no RPM. This is a known OpenSCAP quirk on non-RPM systems.
- **"Unable to open /usr/lib/rpm/rpmrc"** – Same cause; OpenSCAP's platform detection expects RPM.

**Workaround** (optional, to reduce error noise): Create a minimal rpmrc so OpenSCAP can open it:

```bash
sudo mkdir -p /usr/lib/rpm
echo '# Dummy for OpenSCAP CPE on Debian/Ubuntu' | sudo tee /usr/lib/rpm/rpmrc
```

### Expected Scan Results for Minimal Edge Images

For a minimal Kairos/edge image, many STIG rules will **fail** or be **notapplicable** by design:

| Category | Reason |
|----------|--------|
| **AIDE** | File integrity monitoring not typically used on edge nodes |
| **FIPS** | Only for FIPS-enabled build; non-FIPS image will fail `is_fips_mode_enabled` |
| **nss-sss, pam-sss** | SSSD/enterprise identity; not used on standalone edge nodes |
| **vlock, opensc, smartcards** | Session locking and MFA; not on headless edge |
| **AppArmor** | May need configuration; minimal image may not have it |
| **GRUB password** | Requires manual setup; not automated in build |
| **UFW active** | Firewall must be configured for your environment |
| **chrony vs systemd-timesyncd** | STIG prefers chrony; removal of timesyncd may conflict with Kairos |
| **audit-audispd-plugins** | Audit plugin for remote logging |

The remediation script applies rules that are safe for Kubernetes edge nodes. Rules that fail on scan often require environment-specific configuration (e.g., firewall, time sync) or packages not suitable for minimal edge (e.g., AIDE, full SSSD).

## References

- [DISA STIG for Ubuntu](https://public.cyber.mil/stigs/downloads/)
- [OpenSCAP Documentation](https://www.open-scap.org/)
- [scap-security-guide](https://github.com/ComplianceAsCode/content)
