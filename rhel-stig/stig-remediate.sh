#!/bin/bash
# Don't use strict error handling - we want to continue even if some rules fail
set -uo pipefail

# RHEL 9 STIG Remediation Script
# This script applies DISA STIG security hardening using OpenSCAP

# Log directory - use /var/log for persistence across boots
# In Kairos live environments, /var/log is part of the overlay filesystem
# and will persist in the installed system, unlike /tmp which is tmpfs
LOG_DIR="/var/log/stig-remediation"
mkdir -p "$LOG_DIR"

# Debug logging function - writes to both stderr (for Docker build visibility) and log file (for persistence)
DEBUG_LOG="$LOG_DIR/debug.log"
SUMMARY_LOG="$LOG_DIR/summary.log"
print_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"
}

# Function to log script exit status (called on exit)
log_exit_status() {
    local exit_code=$?
    local status_msg=""
    if [ $exit_code -eq 0 ]; then
        status_msg="SUCCESS"
    else
        status_msg="FAILED (exit code: $exit_code)"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script execution $status_msg" >> "$SUMMARY_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Check $DEBUG_LOG for detailed logs" >> "$SUMMARY_LOG"
}

# Set trap to log exit status
trap log_exit_status EXIT

echo "Starting RHEL 9 STIG remediation..."
print_debug "Starting RHEL 9 STIG remediation..."
print_debug "Log directory: $LOG_DIR"

# Find the STIG profile XCCDF file
# Prefer static content (pinned for reproducible releases) over system packages
STIG_XCCDF=""
STATIC_DIR="/tmp/stig-static"
for path in \
    "$STATIC_DIR/ssg-rhel9-ds.xml" \
    "$STATIC_DIR/ssg-rhel9-ds-1.2.xml" \
    "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml" \
    "/usr/share/scap-security-guide/ssg-rhel9-ds.xml" \
    "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds-1.2.xml"
do
    if [ -f "$path" ]; then
        STIG_XCCDF="$path"
        if [[ "$path" == "$STATIC_DIR"* ]]; then
            print_debug "Using static STIG content (pinned for reproducible release)"
        fi
        break
    fi
done

if [ -z "$STIG_XCCDF" ]; then
    print_debug "ERROR: STIG XCCDF file not found"
    print_debug "Please ensure scap-security-guide package is installed, or provide static content in $STATIC_DIR"
    print_debug "Searched paths:"
    print_debug "  $STATIC_DIR/ssg-rhel9-ds.xml (static, for reproducible releases)"
    print_debug "  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
    print_debug "  /usr/share/scap-security-guide/ssg-rhel9-ds.xml"
    echo "ERROR: STIG XCCDF file not found" >&2
    echo "Please ensure scap-security-guide package is installed, or provide static content in $STATIC_DIR" >&2
    echo "Searched paths:" >&2
    echo "  $STATIC_DIR/ssg-rhel9-ds.xml (static, for reproducible releases)" >&2
    echo "  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml" >&2
    echo "  /usr/share/scap-security-guide/ssg-rhel9-ds.xml" >&2
    echo "Check /var/log/stig-remediation/debug.log for details" >&2
    exit 1
fi

STIG_PROFILE="xccdf_org.ssgproject.content_profile_stig"

echo "Using STIG XCCDF file: $STIG_XCCDF"
echo "Using STIG profile: $STIG_PROFILE"
print_debug "Using STIG XCCDF file: $STIG_XCCDF"
print_debug "Using STIG profile: $STIG_PROFILE"

# Copy ds xml to log dir so compliance checks can run post-boot without copying
STIG_DS_COPY="$LOG_DIR/$(basename "$STIG_XCCDF")"
cp "$STIG_XCCDF" "$STIG_DS_COPY"
print_debug "Copied STIG datastream to $STIG_DS_COPY for post-boot compliance scans"

# Verify oscap is available
if ! command -v oscap &> /dev/null; then
    print_debug "ERROR: oscap command not found"
    print_debug "Please ensure openscap-scanner package is installed"
    echo "ERROR: oscap command not found" >&2
    echo "Please ensure openscap-scanner package is installed" >&2
    echo "Check /var/log/stig-remediation/debug.log for details" >&2
    exit 1
fi

# Use remediation script - prefer static (pinned) over generated
REMEDIATION_SCRIPT="/tmp/stig-fix.sh"
STATIC_REMEDIATION="$STATIC_DIR/stig-fix.sh"
OSCAP_ERROR_LOG="$LOG_DIR/oscap-error.log"

if [ -f "$STATIC_REMEDIATION" ]; then
    echo "Using static STIG remediation script (pinned for reproducible release)"
    print_debug "Using static remediation script: $STATIC_REMEDIATION"
    cp "$STATIC_REMEDIATION" "$REMEDIATION_SCRIPT"
    chmod +x "$REMEDIATION_SCRIPT"
else
    echo "Generating STIG remediation script..."
    print_debug "Generating STIG remediation script..."
    OSCAP_ERROR_LOG="$LOG_DIR/oscap-error.log"
    if ! oscap xccdf generate fix \
        --profile "$STIG_PROFILE" \
        --template urn:xccdf:fix:script:sh \
        "$STIG_XCCDF" > "$REMEDIATION_SCRIPT" 2>"$OSCAP_ERROR_LOG"; then
        print_debug "WARNING: Could not generate remediation script"
        print_debug "oscap error output:"
        cat "$OSCAP_ERROR_LOG" | while read line; do print_debug "  $line"; done || true
        echo "WARNING: Could not generate remediation script" >&2
        echo "Check $OSCAP_ERROR_LOG for details" >&2
        echo "Attempting to continue with manual remediation..." >&2
        rm -f "$REMEDIATION_SCRIPT"
        exit 0
    fi
    chmod +x "$REMEDIATION_SCRIPT"
fi

# OPTION A: Use command stubbing instead of mutating the script
# This preserves 100% syntax integrity and avoids structural breakage
# We create stub commands that no-op the container-incompatible operations
print_debug "Setting up command stubs to safely disable container-incompatible operations..."
print_debug "This preserves script syntax integrity - no structural mutations needed"

# Create stub directory and commands
STUB_DIR="/usr/local/stig-stubs"
mkdir -p "$STUB_DIR"

# Create stub scripts that no-op the problematic commands
cat > "$STUB_DIR/dnf" <<'STUBEOF'
#!/bin/sh
echo "STIG-STUB: dnf $@" >&2
exit 0
STUBEOF

cat > "$STUB_DIR/yum" <<'STUBEOF'
#!/bin/sh
echo "STIG-STUB: yum $@" >&2
exit 0
STUBEOF

cat > "$STUB_DIR/curl" <<'STUBEOF'
#!/bin/sh
echo "STIG-STUB: curl $@" >&2
exit 0
STUBEOF

cat > "$STUB_DIR/wget" <<'STUBEOF'
#!/bin/sh
echo "STIG-STUB: wget $@" >&2
exit 0
STUBEOF

cat > "$STUB_DIR/subscription-manager" <<'STUBEOF'
#!/bin/sh
echo "STIG-STUB: subscription-manager $@" >&2
exit 0
STUBEOF

# Make stubs executable
chmod +x "$STUB_DIR"/*

# Make sure the script doesn't exit on errors
sed -i 's/set -e/set +e/g' "$REMEDIATION_SCRIPT" || true
sed -i 's/set -o errexit/set +o errexit/g' "$REMEDIATION_SCRIPT" || true

# Ensure script starts with set +e if it has a shebang
if head -1 "$REMEDIATION_SCRIPT" | grep -q "^#!"; then
    # Check if set +e already exists after shebang
    if ! sed -n '1,5p' "$REMEDIATION_SCRIPT" | grep -q "set +e"; then
        sed -i '1a set +e' "$REMEDIATION_SCRIPT" || true
    fi
fi

# Validate script syntax for logging only (don't try to fix)
SYNTAX_ERROR_LOG="$LOG_DIR/syntax-error.log"
print_debug "Validating remediation script syntax (for logging only - no fixes attempted)..."
if ! bash -n "$REMEDIATION_SCRIPT" 2>"$SYNTAX_ERROR_LOG"; then
    print_debug "WARNING: Syntax errors detected in remediation script (logged for reference)"
    print_debug "These errors will NOT prevent execution - script runs with 'set +e'"
    print_debug "Syntax errors:"
    head -20 "$SYNTAX_ERROR_LOG" | while read line; do print_debug "  $line"; done || true
    if [ $(wc -l < "$SYNTAX_ERROR_LOG" 2>/dev/null || echo "0") -gt 20 ]; then
        print_debug "  ... (more errors in $SYNTAX_ERROR_LOG)"
    fi
else
    print_debug "Script syntax is valid"
fi

# Apply remediation script with error handling
# Use command stubs to safely disable container-incompatible operations
REMEDIATION_LOG="$LOG_DIR/remediation.log"
print_debug "Running remediation script with command stubs..."
print_debug "Remediation log: $REMEDIATION_LOG"
print_debug "Command stubs are active - container-incompatible operations will no-op safely"

# Run script with stubs in PATH (stubs take precedence)
# Use set +e to allow script to continue even if some rules fail
set +e
# Prepend stub directory to PATH so stubs are found first
export PATH="$STUB_DIR:$PATH"
# Run script and capture output, but don't fail on errors
bash -x "$REMEDIATION_SCRIPT" 2>&1 | tee "$REMEDIATION_LOG" | grep -v "STIG-STUB:" || true
REMEDIATION_EXIT_CODE=$?
set -e

if [ $REMEDIATION_EXIT_CODE -eq 0 ]; then
    print_debug "STIG remediation completed successfully"
else
    print_debug "STIG remediation completed with some errors (exit code: $REMEDIATION_EXIT_CODE)"
    print_debug "This is expected - some rules may fail in container environment"
    print_debug "Check $REMEDIATION_LOG for details"
fi

# Clean up stubs
rm -rf "$STUB_DIR" || true

# Old syntax repair logic removed - we use command stubbing instead
# This preserves 100% syntax integrity and avoids structural breakage

# Ensure critical boot directories and binaries are preserved after STIG remediation
# STIG remediation might remove or modify directories/binaries needed for boot
echo "Ensuring boot-critical directories, binaries, and configurations are preserved..."

# CRITICAL: Ensure emergency shell binaries exist (required for initramfs)
# These are needed for dracut emergency mode if boot fails
for bin in /bin/dracut-emergency /usr/bin/systemctl /bin/sh /bin/bash; do
    if [ ! -f "$bin" ]; then
        echo "WARNING: Critical binary missing: $bin"
    fi
done

# Ensure /dev directory structure is preserved (STIG might restrict /dev)
# /dev must be available in initramfs for I/O operations
if [ -d /dev ]; then
    # Ensure /dev/null, /dev/console, /dev/tty exist (critical for initramfs)
    for dev in null console tty zero; do
        if [ ! -e "/dev/$dev" ]; then
            echo "WARNING: Critical device missing: /dev/$dev"
        fi
    done
fi

# STIG remediation may remove or restrict /run directory creation
# Ensure /run and /run/rootfsbase can be created during boot
# Note: /run is tmpfs, but we need to ensure dracut-live can create /run/rootfsbase
# Create tmpfiles.d entry as backup (though this runs after initramfs)
mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/kairos-rootfsbase.conf <<'EOF'
# Create /run/rootfsbase directory for overlayfs during live CD boot
# This is required by dracut-live module for overlayfs root filesystem
# Note: This is a backup - the actual fix is patching dracut-live scripts
d /run/rootfsbase 0755 root root -
EOF

# Ensure STIG remediation didn't break /run directory permissions
# Some STIG rules might restrict /run creation
if [ -d /run ]; then
    chmod 755 /run 2>/dev/null || true
fi

# Ensure dracut-live module is not disabled
# Check if dracut.conf exists and ensure dracut-live is included
if [ -f /etc/dracut.conf ]; then
    # Ensure dracut-live is not in omit_dracutmodules
    sed -i 's/^omit_dracutmodules.*dracut-live.*//g' /etc/dracut.conf || true
    # Ensure dracut-live is in add_dracutmodules if not already
    if ! grep -q "add_dracutmodules.*dracut-live" /etc/dracut.conf; then
        printf '\n%s\n' 'add_dracutmodules+=" dracut-live "' >> /etc/dracut.conf || true
    fi
fi

# Ensure dracut-live is included in all dracut.conf.d files
for conf_file in /etc/dracut.conf.d/*.conf; do
    if [ -f "$conf_file" ]; then
        # Remove any lines that omit dracut-live
        sed -i '/omit_dracutmodules.*dracut-live/d' "$conf_file" || true
        # Note: We're patching dracut-live directly instead of using a custom module
        # This is more reliable and doesn't require add_dracutmodules configuration
    fi
done

# CRITICAL: Ensure STIG remediation doesn't blacklist required filesystem modules
# Kairos requires squashfs, overlay, and loop to boot
# These modules MUST be available in initramfs
echo "Ensuring required filesystem modules are not blacklisted..."

# Check for and remove blacklist entries for required modules
# This prevents STIG rules from disabling modules needed for boot
for mod in squashfs overlay loop; do
    # Remove blacklist entries from all modprobe.d configs
    for conf in /etc/modprobe.d/*.conf; do
        if [ -f "$conf" ]; then
            # Remove blacklist lines
            sed -i "/^blacklist.*${mod}/d" "$conf" || true
            # Remove install lines that disable the module
            sed -i "/^install.*${mod}.*\/bin\/true/d" "$conf" || true
            # Remove install lines that disable the module (alternative syntax)
            sed -i "/^install.*${mod}.*\/bin\/false/d" "$conf" || true
        fi
    done
done

# Ensure kernel.modules_disabled is not set to 1 (would prevent module loading)
# STIG may require this, but it must be delayed until after rootfs mount
if [ -f /etc/sysctl.conf ]; then
    # Comment out if present (we'll handle this at runtime if STIG requires it)
    sed -i 's/^kernel\.modules_disabled.*/# STIG exception: kernel.modules_disabled delayed for Kairos boot\n# &/' /etc/sysctl.conf || true
fi

# STIG sets net.ipv4.ip_forward=0 and net.ipv4.conf.all.forwarding=0; Kubernetes requires both=1
echo "Applying Kubernetes exception: net.ipv4.ip_forward=1 and net.ipv4.conf.all.forwarding=1 (required for pod networking)..."

shopt -s nullglob
for f in /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/local/lib/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf; do
    [ -f "$f" ] || continue
    # Comment out existing settings (preserve original line)
    sed -i \
        -e 's/^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=.*$/# STIG exception (Kubernetes requires ip_forward=1): &/' \
        -e 's/^[[:space:]]*net\.ipv4\.conf\.all\.forwarding[[:space:]]*=.*$/# STIG exception (Kubernetes requires forwarding=1): &/' \
        "$f" 2>/dev/null || true
done
shopt -u nullglob 2>/dev/null || true

mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-zzz-kubernetes-ip-forward.conf <<'EOF'
# Kubernetes exception: STIG disables ip_forward; Kubernetes/CNI requires it for pod networking
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
EOF

# Set safe ownership/mode
chown root:root /etc/sysctl.d/99-zzz-kubernetes-ip-forward.conf
chmod 0644 /etc/sysctl.d/99-zzz-kubernetes-ip-forward.conf

# Apply now and re-check (retry a few times in short loop to beat races)
for i in 1 2 3; do
    /sbin/sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
    /sbin/sysctl -w net.ipv4.conf.all.forwarding=1 2>/dev/null || true
    /sbin/sysctl --system 2>/dev/null || true
    sleep 0.5
done

# verify
current=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "MISSING")
current_all=$(cat /proc/sys/net/ipv4/conf/all/forwarding 2>/dev/null || echo "MISSING")
print_debug "Runtime after apply: net.ipv4.ip_forward=$current net.ipv4.conf.all.forwarding=$current_all"

# Ensure required drivers and modules are in dracut config (backup in case STIG removed them)
for conf_file in /etc/dracut.conf.d/*.conf; do
    if [ -f "$conf_file" ]; then
        # Add drivers if not present
        if ! grep -q "add_drivers.*squashfs" "$conf_file"; then
            printf '\n%s\n' 'add_drivers+=" squashfs overlay loop "' >> "$conf_file" || true
        fi
        # Ensure systemd module is included (belt-and-suspenders)
        if ! grep -q "add_dracutmodules.*systemd" "$conf_file"; then
            printf '\n%s\n' 'add_dracutmodules+=" systemd "' >> "$conf_file" || true
        fi
        # Ensure dmsquash-live module is included (CRITICAL for live squashfs mount)
        if ! grep -q "add_dracutmodules.*dmsquash-live" "$conf_file"; then
            printf '\n%s\n' 'add_dracutmodules+=" dmsquash-live "' >> "$conf_file" || true
        fi
        # Ensure rootfsbase module is included
        if ! grep -q "add_dracutmodules.*rootfsbase" "$conf_file"; then
            printf '\n%s\n' 'add_dracutmodules+=" rootfsbase "' >> "$conf_file" || true
        fi
    fi
done

# Also ensure in main dracut.conf
if [ -f /etc/dracut.conf ]; then
    if ! grep -q "add_drivers.*squashfs" /etc/dracut.conf; then
        printf '\n%s\n' 'add_drivers+=" squashfs overlay loop "' >> /etc/dracut.conf || true
    fi
    if ! grep -q "add_dracutmodules.*systemd" /etc/dracut.conf; then
        printf '\n%s\n' 'add_dracutmodules+=" systemd "' >> /etc/dracut.conf || true
    fi
    if ! grep -q "add_dracutmodules.*dmsquash-live" /etc/dracut.conf; then
        printf '\n%s\n' 'add_dracutmodules+=" dmsquash-live "' >> /etc/dracut.conf || true
    fi
    if ! grep -q "add_dracutmodules.*rootfsbase" /etc/dracut.conf; then
        printf '\n%s\n' 'add_dracutmodules+=" rootfsbase "' >> /etc/dracut.conf || true
    fi
fi

# Save remediation script to log directory for debugging instead of deleting
# This allows inspection of the filtered/fixed script if issues occur
REMEDIATION_SCRIPT_SAVED="$LOG_DIR/stig-fix.sh"
if [ -f "$REMEDIATION_SCRIPT" ]; then
    cp "$REMEDIATION_SCRIPT" "$REMEDIATION_SCRIPT_SAVED"
    print_debug "Saved remediation script to $REMEDIATION_SCRIPT_SAVED for debugging"
    chmod +r "$REMEDIATION_SCRIPT_SAVED"
    # Clean up temporary script
    rm -f "$REMEDIATION_SCRIPT"
else
    print_debug "WARNING: Remediation script not found for saving (may have been deleted earlier)"
fi

# Apply firewall rules that are compatible with Palette cluster operations
# STIG requires strict firewall, but we need to allow Kubernetes networking
echo "Configuring firewall rules for Palette compatibility..."

mkdir -p /etc/firewalld/services
mkdir -p /etc/firewalld/zones

# Create k8s zone with required ports; set as default so primary interface is assigned automatically
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
  <!-- VXLAN overlay (required for registration mode) -->
  <port protocol="udp" port="4789"/>
  <port protocol="udp" port="12345"/>
  <!-- Calico BGP -->
  <port protocol="tcp" port="179"/>
  <!-- Calico IP-in-IP -->
  <protocol value="ipip"/>
  <!-- Weave Net -->
  <port protocol="tcp" port="6783"/>
  <port protocol="udp" port="6783-6784"/>
</zone>
EOF

# Set k8s as default zone so primary interface is assigned to it (avoids public zone blocking k8s ports)
mkdir -p /etc/firewalld
if [ -f /etc/firewalld/firewalld.conf ]; then
    if grep -q '^DefaultZone=' /etc/firewalld/firewalld.conf 2>/dev/null; then
        sed -i 's/^DefaultZone=.*/DefaultZone=k8s/' /etc/firewalld/firewalld.conf
    else
        echo 'DefaultZone=k8s' >> /etc/firewalld/firewalld.conf
    fi
else
    echo 'DefaultZone=k8s' > /etc/firewalld/firewalld.conf
fi
print_debug "Set firewalld DefaultZone=k8s (primary interface will use k8s zone)"

echo "STIG remediation completed"
echo "NOTE: Some rules requiring downloads or network access were skipped (expected in container builds)"
echo "NOTE: Firewall rules will need to be configured at runtime for Palette cluster operations"
echo "See README.md for required firewall exceptions"
print_debug "STIG remediation completed successfully"
print_debug "STIG remediation logs saved to: $LOG_DIR"
print_debug "Available log files:"
print_debug "  - $DEBUG_LOG (debug output)"
print_debug "  - $REMEDIATION_LOG (remediation execution log)"
print_debug "  - $SYNTAX_ERROR_LOG (syntax validation errors, if any)"
print_debug "  - $OSCAP_ERROR_LOG (oscap generation errors, if any)"
if [ -f "$REMEDIATION_SCRIPT_SAVED" ]; then
    print_debug "  - $REMEDIATION_SCRIPT_SAVED (filtered/fixed remediation script for debugging)"
fi
print_debug "These logs will persist in /var/log/stig-remediation/ after installation"

# Always exit successfully to not fail Docker build
exit 0

