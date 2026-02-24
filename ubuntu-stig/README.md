# Kairos Ubuntu 24.04 STIG

This directory contains Dockerfiles and build scripts for creating Ubuntu 24.04 STIG-compliant base images for use with Palette Edge clusters.

## Overview

Ubuntu 24.04 STIG (Security Technical Implementation Guide) compliance is required for regulated and government customers running Palette-managed clusters. These images apply DISA STIG security hardening using OpenSCAP and scap-security-guide.

## Build Ubuntu 24.04 STIG Image

### Prerequisites

- Docker installed and running
- Access to Ubuntu repositories (Ubuntu 24.04 packages required)
- No subscription required (Ubuntu packages are freely available)

### Building Non-FIPS STIG Image

```bash
bash build.sh.ubuntu24.04 [<base image name>] [false]
```

Example:
```bash
bash build.sh.ubuntu24.04 ubuntu24.04-byoi-stig false
```

### Building FIPS STIG Image

**Ubuntu Pro Token Required**: FIPS-certified packages require an Ubuntu Pro subscription token.

**Option 1: Using build script with token**
```bash
bash build.sh.ubuntu24.04 [<base image name>] [true] [<ubuntu-pro-token>]
```

Example:
```bash
bash build.sh.ubuntu24.04 ubuntu24.04-byoi-stig-fips true YOUR_UBUNTU_PRO_TOKEN
```

**Option 2: Using Docker secret (recommended)**
```bash
# Create pro-attach-config.yaml with your token
cat > pro-attach-config.yaml <<EOF
token: "YOUR_UBUNTU_PRO_TOKEN"
enable_services:
  - fips-updates
EOF

# Build with secret
docker build --secret id=pro-attach-config,src=pro-attach-config.yaml \
             --build-arg KAIROS_VERSION=v3.5.9 \
             -t ubuntu24.04-byoi-stig-fips \
             -f Dockerfile.ubuntu24.04-fips .
```

**Note**: 
- Non-FIPS STIG images do not require Ubuntu Pro subscription
- FIPS-certified packages require Ubuntu Pro subscription
- Get your Ubuntu Pro token from https://ubuntu.com/pro

## Using the Base Image

After building the base image, you need to make it available to Earthly. Earthly requires the image to be in a Docker registry (not just locally). You have two options:

### Option 1: Push to a Docker Registry (Recommended)

1. Tag the image with your registry:
   ```bash
   # For non-FIPS
   docker tag ubuntu24.04-byoi-stig <your-registry>/ubuntu24.04-byoi-stig:latest
   docker push <your-registry>/ubuntu24.04-byoi-stig:latest
   
   # For FIPS
   docker tag ubuntu24.04-byoi-stig-fips <your-registry>/ubuntu24.04-byoi-stig-fips:latest
   docker push <your-registry>/ubuntu24.04-byoi-stig-fips:latest
   ```

2. Use the full registry path in Earthly:
   ```bash
   # For non-FIPS
   ./earthly.sh +iso --BASE_IMAGE=<your-registry>/ubuntu24.04-byoi-stig:latest --OS_DISTRIBUTION=ubuntu --ARCH=amd64
   
   # For FIPS
   ./earthly.sh +iso --BASE_IMAGE=<your-registry>/ubuntu24.04-byoi-stig-fips:latest --OS_DISTRIBUTION=ubuntu --FIPS_ENABLED=true --ARCH=amd64
   ```

### Option 2: Use Local Registry or Docker Hub

If using Docker Hub:
```bash
# Tag and push to Docker Hub
docker tag ubuntu24.04-byoi-stig <your-dockerhub-username>/ubuntu24.04-byoi-stig:latest
docker push <your-dockerhub-username>/ubuntu24.04-by-toi-stig:latest

# Then use in Earthly
./earthly.sh +iso --BASE_IMAGE=<your-dockerhub-username>/ubuntu24.04-byoi-stig:latest --OS_DISTRIBUTION=ubuntu --ARCH=amd64
```

**Important**: Earthly cannot use local-only Docker images. The image must be pushed to a registry that Earthly can access.

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

STIG requires strict firewall rules, but Palette cluster operations require specific ports to be open. Ubuntu uses `ufw` (Uncomplicated Firewall) instead of `firewalld`. The build process creates a ufw application profile template (`/etc/ufw/applications.d/k8s`) and a configuration script (`/usr/local/bin/configure-ufw-k8s.sh`) that includes:

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

**Note**: Firewall rules must be configured at runtime via cloud-init/user-data. The base image includes templates but does not activate firewall rules during build to avoid breaking the build process.

### Runtime Firewall Configuration

To configure firewall at runtime, add the following to your `user-data`:

```yaml
#cloud-config
stages:
  boot.after:
    - name: Configure firewall for Kubernetes
      commands:
        - /usr/local/bin/configure-ufw-k8s.sh
```

Or manually configure ufw:

```yaml
#cloud-config
stages:
  boot.after:
    - name: Configure firewall for Kubernetes
      commands:
        - ufw --force enable
        - ufw allow ssh
        - ufw allow 6443/tcp comment 'Kubernetes API server'
        - ufw allow 2379:2380/tcp comment 'etcd server client API'
        - ufw allow 10250/tcp comment 'Kubelet API'
        - ufw allow 10259/tcp comment 'kube-scheduler'
        - ufw allow 10257/tcp comment 'kube-controller-manager'
        - ufw allow 30000:32767/tcp comment 'NodePort Services TCP'
        - ufw allow 30000:32767/udp comment 'NodePort Services UDP'
        - ufw allow 8472/udp comment 'Flannel VXLAN'
        - ufw allow 179/tcp comment 'Calico BGP'
        - ufw allow 6783/tcp comment 'Weave Net'
        - ufw allow 6783:6784/udp comment 'Weave Net UDP'
        - ufw reload
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
    extra_cmdline: "fips=1"
```

**Notes:**
- Ubuntu FIPS support requires Ubuntu Pro subscription for FIPS-certified packages
- The LiveCD is not running in FIPS mode
- Ubuntu uses AppArmor instead of SELinux (AppArmor is enabled by default)

## Verify STIG Compliance

After installation, you can verify STIG compliance by running:

```bash
# Check STIG profile compliance
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_stig \
  --results stig-results.xml \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

# Generate HTML report
oscap xccdf generate report stig-results.xml > stig-report.html
```

## Verify FIPS is Enabled (FIPS variant only)

After install, verify that FIPS is enabled:

```bash
cat /proc/sys/crypto/fips_enabled
# Should output: 1
```

## Known Issues and Limitations

1. **AppArmor**: Ubuntu uses AppArmor instead of SELinux. AppArmor is enabled by default and STIG compliance requires it to be active.

2. **Container Build Environment**: Some STIG remediation rules may fail during container build as they are designed for running systems. These are logged but do not fail the build.

3. **Firewall Rules**: Firewall must be configured at runtime. The build process creates templates but does not activate firewall during build.

4. **LiveCD vs Installed System**: STIG compliance is applied to the installed system. The LiveCD environment may not be fully STIG-compliant.

5. **Ubuntu Pro**: FIPS-certified packages require Ubuntu Pro subscription. Non-FIPS STIG images do not require Ubuntu Pro.

## Troubleshooting

### Build Fails with Package Errors

Ensure you have access to Ubuntu repositories:
- `jammy main` repository
- `scap-security-guide` package
- `openscap-scanner` package
- FIPS packages (for FIPS variant, requires Ubuntu Pro)

### STIG Remediation Warnings

Some remediation rules may show warnings during build. This is expected in container environments. Review `/var/log/stig-remediation/remediation.log` for details. All STIG remediation logs are saved to `/var/log/stig-remediation/` and will persist after installation.

### Firewall Blocking Cluster Operations

If cluster operations are blocked by firewall:
1. Verify ufw is configured correctly: `ufw status verbose`
2. Check that required Kubernetes ports are open: `ufw status numbered`
3. Review firewall logs: `journalctl -u ufw`

### Ubuntu Pro FIPS Requirements

For FIPS variant, ensure Ubuntu Pro is properly configured:
- Ubuntu Pro subscription token is available
- FIPS packages are accessible
- Verify with: `pro status`

## References

- [DISA STIG for Ubuntu 24.04](https://public.cyber.mil/stigs/downloads/)
- [OpenSCAP Documentation](https://www.open-scap.org/)
- [scap-security-guide](https://github.com/ComplianceAsCode/content)
- [Ubuntu Pro Documentation](https://ubuntu.com/pro)
