# Ubuntu 24.04 STIG

This directory contains Dockerfiles and build scripts for creating Ubuntu 24.04 STIG-compliant base images for use with Palette Edge clusters.

## Overview

Ubuntu 24.04 STIG (Security Technical Implementation Guide) compliance is required for regulated and government customers. These images apply DISA STIG security hardening using OpenSCAP and scap-security-guide.

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

To use the latest STIG guide and remediation instead of the pinned release:

- Omit the static content: ensure `static/` contains only `VERSION` (or no XCCDF/stig-fix.sh)
- The build will use system packages and generate remediation from the installed `scap-security-guide`
- Or run `scripts/update-stig-content.sh v0.1.XX` with a newer version before building

**Source**: [ComplianceAsCode/content releases](https://github.com/ComplianceAsCode/content/releases)

## Build Requirements

The update script (`scripts/update-stig-content.sh`) requires build dependencies:

- **Ubuntu**: `apt install cmake make libopenscap8 openscap-utils openscap-scanner python3 python3-pip`

## References

- [DISA STIG for Ubuntu](https://public.cyber.mil/stigs/downloads/)
- [OpenSCAP Documentation](https://www.open-scap.org/)
- [scap-security-guide](https://github.com/ComplianceAsCode/content)
