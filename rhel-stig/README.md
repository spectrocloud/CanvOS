# Kairos RHEL 9 STIG

This directory contains Dockerfiles and build scripts for creating RHEL 9 STIG-compliant base images for use with Palette Edge clusters.

## Overview

RHEL 9 STIG (Security Technical Implementation Guide) compliance is required for regulated and government customers running Palette-managed clusters. These images apply DISA STIG security hardening using OpenSCAP and scap-security-guide.

## Build RHEL 9 STIG Image

### Prerequisites

- Red Hat subscription credentials (username and password)
- Docker installed and running
- Access to Red Hat repositories (RHEL 9 packages required)

### Building Non-FIPS STIG Image

```bash
bash build.sh.rhel9 <username> <password> [<base image name>] [false]
```

Example:
```bash
bash build.sh.rhel9 myuser@example.com mypassword rhel9-byoi-stig false
```

### Building FIPS STIG Image

```bash
bash build.sh.rhel9 <username> <password> [<base image name>] [true]
```

Example:
```bash
bash build.sh.rhel9 myuser@example.com mypassword rhel9-byoi-stig-fips true
```

**Note**: Red Hat subscription credentials are required to build these images as RHEL 9 STIG packages are only available through Red Hat repositories.

## Using the Base Image

After building the base image, you need to make it available to Earthly. Earthly requires the image to be in a Docker registry (not just locally). You have two options:

### Option 1: Push to a Docker Registry (Recommended)

1. Tag the image with your registry:
   ```bash
   # For non-FIPS
   docker tag rhel9-byoi-stig <your-registry>/rhel9-byoi-stig:latest
   docker push <your-registry>/rhel9-byoi-stig:latest
   
   # For FIPS
   docker tag rhel9-byoi-stig-fips <your-registry>/rhel9-byoi-stig-fips:latest
   docker push <your-registry>/rhel9-byoi-stig-fips:latest
   ```

2. Use the full registry path in Earthly:
   ```bash
   # For non-FIPS
   ./earthly.sh +iso --BASE_IMAGE=<your-registry>/rhel9-byoi-stig:latest --OS_DISTRIBUTION=rhel --ARCH=amd64
   
   # For FIPS
   ./earthly.sh +iso --BASE_IMAGE=<your-registry>/rhel9-byoi-stig-fips:latest --OS_DISTRIBUTION=rhel --FIPS_ENABLED=true --ARCH=amd64
   ```

### Option 2: Use Local Registry or Docker Hub

If using Docker Hub:
```bash
# Tag and push to Docker Hub
docker tag rhel9-byoi-stig <your-dockerhub-username>/rhel9-byoi-stig:latest
docker push <your-dockerhub-username>/rhel9-byoi-stig:latest

# Then use in Earthly
./earthly.sh +iso --BASE_IMAGE=<your-dockerhub-username>/rhel9-byoi-stig:latest --OS_DISTRIBUTION=rhel --ARCH=amd64
```

**Important**: Earthly cannot use local-only Docker images. The image must be pushed to a registry that Earthly can access.

## Static STIG Content (Reproducible Releases)

To ensure released base images use a **verified, pinned** STIG guide and remediation (avoiding unforeseen changes that could affect Kubernetes clusters), we support static STIG content:

1. **Before a release**, run the update script to download and pin STIG content:
   ```bash
   cd rhel-stig
   bash scripts/update-stig-content.sh v0.1.79
   ```
   This downloads the ComplianceAsCode release, builds the RHEL 9 datastream, and generates the remediation script into `static/`.

2. **Build with static content**: Ensure `static/` contains `ssg-rhel9-ds.xml` and `stig-fix.sh` before building. The Dockerfile copies these into the image.

3. **Without static content**: The build falls back to system-installed `scap-security-guide` and generates remediation at build time. This uses whatever version is in the base image's repositories.

### Using Latest STIG (for customers who want current content)

To use the latest STIG guide and remediation instead of the pinned release:

- Omit the static content: ensure `static/` contains only `VERSION` (or no XCCDF/stig-fix.sh)
- The build will use system packages and generate remediation from the installed `scap-security-guide`
- Or run `scripts/update-stig-content.sh v0.1.XX` with a newer version before building

### Checking the Latest STIG Version

To find the latest ComplianceAsCode release version before running the update script:

```bash
# Via GitHub API (requires jq)
curl -s https://api.github.com/repos/ComplianceAsCode/content/releases/latest | jq -r .tag_name

# Via git (no API)
git ls-remote --tags https://github.com/ComplianceAsCode/content.git | tail -1 | sed 's|.*refs/tags/||'
```

Then run the update script with that version:
```bash
./scripts/update-stig-content.sh v0.1.XX
```

**Source**: [ComplianceAsCode/content releases](https://github.com/ComplianceAsCode/content/releases)

**Update script requirements**: `cmake`, `make`, `openscap-utils`, `openscap-scanner`, `python3`, `pip`  
RHEL/Fedora: `dnf install cmake make openscap-utils openscap-scanner python3 python3-pip`

## STIG Compliance

The images apply DISA STIG security hardening using:
- **scap-security-guide**: Provides STIG profiles and benchmarks
- **openscap-scanner**: Applies remediation rules
- **Profile**: `xccdf_org.ssgproject.content_profile_stig`

### Applied Remediations

The build process automatically applies STIG remediation rules including:
- SSH cryptographic settings (approved ciphers, MACs, key exchange algorithms)
- File permissions and ownership
- Audit configuration
- Firewall rules (with Palette-compatible exceptions)
- System hardening settings

### Firewall Configuration

STIG requires strict firewall rules, but Palette cluster operations require specific ports to be open. The build process creates a custom firewall zone template (`/etc/firewalld/zones/k8s.xml`) that includes:

**Required Ports for Kubernetes:**
- **6443/tcp**: Kubernetes API server
- **2379-2380/tcp**: etcd server client API
- **10250/tcp**: Kubelet API
- **10259/tcp**: kube-scheduler
- **10257/tcp**: kube-controller-manager
- **30000-32767/tcp,udp**: NodePort Services
- **8472/udp**: Flannel VXLAN
- **179/tcp**: Calico BGP
- **6783-6784/tcp,udp**: Weave Net

**Note**: Firewall rules must be configured at runtime via cloud-init/user-data. The base image includes a template but does not activate firewall rules during build to avoid breaking the build process.

### Runtime Firewall Configuration

To configure firewall at runtime, add the following to your `user-data`:

```yaml
#cloud-config
stages:
  boot.after:
    - name: Configure firewall for Kubernetes
      commands:
        - firewall-cmd --permanent --new-zone=k8s || true
        - firewall-cmd --permanent --zone=k8s --add-service=ssh
        - firewall-cmd --permanent --zone=k8s --add-service=dhcpv6-client
        - firewall-cmd --permanent --zone=k8s --add-port=6443/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=2379-2380/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=10250/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=10259/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=10257/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=30000-32767/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=30000-32767/udp
        - firewall-cmd --permanent --zone=k8s --add-port=8472/udp
        - firewall-cmd --permanent --zone=k8s --add-port=179/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=6783-6784/tcp
        - firewall-cmd --permanent --zone=k8s --add-port=6783-6784/udp
        - firewall-cmd --permanent --zone=k8s --add-protocol=ipip
        - firewall-cmd --set-default-zone=k8s
        - firewall-cmd --reload
```

## FIPS Mode

For FIPS-enabled STIG images:

1. The system is not enabling FIPS by default in kernel space during the LiveCD phase
2. To install with FIPS, you need a cloud-config file adding `fips=1` to the boot options:

```yaml
#cloud-config
install:
  # ...
  # Set grub options
  grub_options:
    # additional Kernel option cmdline to apply
    extra_cmdline: "fips=1 selinux=0"
```

**Notes:**
- Most Dockerfile configuration includes packages installed by RHEL 9 and framework files from Kairos containing FIPS-enabled packages
- The LiveCD is not running in FIPS mode
- You must add `selinux=0`. SELinux is not supported yet and must be explicitly disabled
- Red Hat subscription is required for access to FIPS-compliant packages

## Running OpenSCAP Scans (Post-Install)

To run a scan on a deployed node:

```bash
# The ds xml is copied to the stig-remediation log dir during build (e.g. ssg-rhel9-ds.xml)
XCCDF="/var/log/stig-remediation/ssg-rhel9-ds.xml"

oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig \
  --report report.html "$XCCDF"
```

### Known OpenSCAP Errors

You may see these non-fatal errors; the scan still completes and produces results:

- **"Unknown IO error" / "cpelang_priv.c"** – OpenSCAP's CPE (Common Platform Enumeration) code path can emit these errors during platform detection. This occurs on both RHEL and Ubuntu. The scan completes and produces valid results.

### Expected Scan Results for Minimal Edge Images

For a minimal Kairos/edge image, many STIG rules will **fail** or be **notapplicable** by design:

| Category | Reason |
|----------|--------|
| **AIDE** | File integrity monitoring not typically used on edge nodes |
| **FIPS** | Only for FIPS-enabled build; non-FIPS image will fail FIPS checks |
| **Mount options** | `/tmp`, `/var/log`, `/dev/shm`, etc. – Kairos layout differs from traditional partitioning |
| **GRUB** | `init_on_free`, PTI, vsyscall, password – require kernel/GRUB changes |
| **Packages** | chrony, cron, fapolicyd, postfix, s-nail, nfs-utils, usbguard, libreswan |
| **Partitions** | `/var/log/audit`, `/var/tmp` – edge layout may not match STIG expectations |
| **User namespaces** | `sysctl_user_max_user_namespaces` – may conflict with containers |
| **SELinux** | Policy configuration (e.g. `selinux_context_elevation_for_sudo`) |
| **Firewall** | SSH firewalld exception – environment-specific |

The remediation script applies rules that are safe for Kubernetes edge nodes. Rules that fail on scan often require environment-specific configuration or packages not suitable for minimal edge.

## Verify FIPS is Enabled (FIPS variant only)

After install, verify that FIPS is enabled:

```bash
cat /proc/sys/crypto/fips_enabled
# Should output: 1
```

## Known Issues and Limitations

1. **SELinux**: Currently disabled (`SELINUX=disabled`) as SELinux is not yet supported in Kairos. STIG compliance may require SELinux to be enabled in production environments.

2. **Container Build Environment**: Some STIG remediation rules may fail during container build as they are designed for running systems. These are logged but do not fail the build.

3. **Firewall Rules**: Firewall must be configured at runtime. The build process creates templates but does not activate firewall during build.

4. **LiveCD vs Installed System**: STIG compliance is applied to the installed system. The LiveCD environment may not be fully STIG-compliant.

## Troubleshooting

### Build Fails with Subscription Errors

Ensure your Red Hat subscription credentials are correct and have access to:
- `rhel-9-for-x86_64-appstream-rpms` repository
- `scap-security-guide` package
- FIPS packages (for FIPS variant)

### STIG Remediation Warnings

Some remediation rules may show warnings during build. This is expected in container environments. Review `/var/log/stig-remediation/remediation.log` for details. All STIG remediation logs are saved to `/var/log/stig-remediation/` and will persist after installation.

### Firewall Blocking Cluster Operations

If cluster operations are blocked by firewall:
1. Verify firewall zone is configured correctly
2. Check that required Kubernetes ports are open
3. Review firewall logs: `journalctl -u firewalld`

## References

- [DISA STIG for RHEL 9](https://public.cyber.mil/stigs/downloads/)
- [OpenSCAP Documentation](https://www.open-scap.org/)
- [scap-security-guide](https://github.com/ComplianceAsCode/content)

