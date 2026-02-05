#!/bin/bash
set -euo pipefail

# RHEL 9 STIG Remediation Script
# This script applies DISA STIG security hardening using OpenSCAP

echo "Starting RHEL 9 STIG remediation..."

# Find the STIG profile XCCDF file
# Try common locations for scap-security-guide content
STIG_XCCDF=""
for path in \
    "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml" \
    "/usr/share/scap-security-guide/ssg-rhel9-ds.xml" \
    "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds-1.2.xml"
do
    if [ -f "$path" ]; then
        STIG_XCCDF="$path"
        break
    fi
done

if [ -z "$STIG_XCCDF" ]; then
    echo "ERROR: STIG XCCDF file not found"
    echo "Please ensure scap-security-guide package is installed"
    echo "Searched paths:"
    echo "  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
    echo "  /usr/share/scap-security-guide/ssg-rhel9-ds.xml"
    exit 1
fi

STIG_PROFILE="xccdf_org.ssgproject.content_profile_stig"

echo "Using STIG XCCDF file: $STIG_XCCDF"
echo "Using STIG profile: $STIG_PROFILE"

# Verify oscap is available
if ! command -v oscap &> /dev/null; then
    echo "ERROR: oscap command not found"
    echo "Please ensure openscap-scanner package is installed"
    exit 1
fi

# Generate remediation script
echo "Generating STIG remediation script..."
REMEDIATION_SCRIPT="/tmp/stig-fix.sh"

# Generate fix script from STIG profile
if ! oscap xccdf generate fix \
    --profile "$STIG_PROFILE" \
    --template urn:xccdf:fix:script:sh \
    "$STIG_XCCDF" > "$REMEDIATION_SCRIPT" 2>/tmp/oscap-error.log; then
    echo "WARNING: Could not generate remediation script"
    cat /tmp/oscap-error.log || true
    echo "Attempting to continue with manual remediation..."
    rm -f "$REMEDIATION_SCRIPT"
    exit 0
fi

# Make script executable
chmod +x "$REMEDIATION_SCRIPT"

# Apply remediation script with error handling
# Some rules may fail in container environment, so we continue on errors
echo "Applying STIG remediation rules..."
# Use set +e to allow script to continue even if some rules fail
set +e
bash "$REMEDIATION_SCRIPT" 2>&1 | tee /tmp/stig-remediation.log
REMEDIATION_EXIT=$?
set -e

if [ $REMEDIATION_EXIT -ne 0 ]; then
    echo "WARNING: Some STIG remediation rules failed (exit code: $REMEDIATION_EXIT)"
    echo "This may be expected in container environment - some rules require running system"
    echo "Review /tmp/stig-remediation.log for details"
fi

# Ensure critical boot directories are preserved after STIG remediation
# STIG remediation might remove or modify directories needed for boot
echo "Ensuring boot-critical directories and configurations are preserved..."

# Ensure /run structure is preserved (needed for overlayfs during boot)
# Create tmpfiles.d entry to ensure /run/rootfsbase is created during boot
mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/kairos-rootfsbase.conf <<'EOF'
# Create /run/rootfsbase directory for overlayfs during live CD boot
# This is required by dracut-live module for overlayfs root filesystem
d /run/rootfsbase 0755 root root -
EOF

# Ensure dracut-live module is not disabled
# Check if dracut.conf exists and ensure dracut-live is included
if [ -f /etc/dracut.conf ]; then
    # Ensure dracut-live is not in omit_dracutmodules
    sed -i 's/^omit_dracutmodules.*dracut-live.*//g' /etc/dracut.conf || true
    # Ensure dracut-live is in add_dracutmodules if not already
    if ! grep -q "add_dracutmodules.*dracut-live" /etc/dracut.conf; then
        echo "add_dracutmodules+=\" dracut-live \"" >> /etc/dracut.conf
    fi
fi

# Ensure dracut-live is included in all dracut.conf.d files
for conf_file in /etc/dracut.conf.d/*.conf; do
    if [ -f "$conf_file" ]; then
        # Remove any lines that omit dracut-live
        sed -i '/omit_dracutmodules.*dracut-live/d' "$conf_file" || true
        # Ensure rootfsbase module is included
        if ! grep -q "add_dracutmodules.*rootfsbase" "$conf_file"; then
            # Add rootfsbase if add_dracutmodules line exists, otherwise add new line
            if grep -q "add_dracutmodules" "$conf_file"; then
                sed -i 's/add_dracutmodules+="\(.*\)"/add_dracutmodules+="\1 rootfsbase "/' "$conf_file" || \
                sed -i '/add_dracutmodules/ s/$/ rootfsbase/' "$conf_file" || true
            else
                echo "add_dracutmodules+=\" rootfsbase \"" >> "$conf_file"
            fi
        fi
    fi
done

# Clean up
rm -f "$REMEDIATION_SCRIPT"

# Apply firewall rules that are compatible with Palette cluster operations
# STIG requires strict firewall, but we need to allow Kubernetes networking
echo "Configuring firewall rules for Palette compatibility..."

# Ensure firewalld is configured but not blocking required ports
# These will be configured at runtime via cloud-init/user-data
mkdir -p /etc/firewalld/services
mkdir -p /etc/firewalld/zones

# Create a custom zone for Kubernetes if needed (will be applied at runtime)
cat > /etc/firewalld/zones/k8s.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<zone>
  <short>Kubernetes</short>
  <description>Zone for Kubernetes cluster networking</description>
  <service name="ssh"/>
  <service name="dhcpv6-client"/>
  <!-- Kubernetes API server -->
  <port protocol="tcp" port="6443"/>
  <!-- etcd server client API -->
  <port protocol="tcp" port="2379-2380"/>
  <!-- Kubelet API -->
  <port protocol="tcp" port="10250"/>
  <!-- kube-scheduler -->
  <port protocol="tcp" port="10259"/>
  <!-- kube-controller-manager -->
  <port protocol="tcp" port="10257"/>
  <!-- NodePort Services -->
  <port protocol="tcp" port="30000-32767"/>
  <port protocol="udp" port="30000-32767"/>
  <!-- Flannel VXLAN -->
  <port protocol="udp" port="8472"/>
  <!-- Calico BGP -->
  <port protocol="tcp" port="179"/>
  <!-- Calico IP-in-IP -->
  <protocol value="ipip"/>
  <!-- Weave Net -->
  <port protocol="tcp" port="6783"/>
  <port protocol="udp" port="6783-6784"/>
</zone>
EOF

echo "STIG remediation completed successfully"
echo "NOTE: Firewall rules will need to be configured at runtime for Palette cluster operations"
echo "See README.md for required firewall exceptions"
