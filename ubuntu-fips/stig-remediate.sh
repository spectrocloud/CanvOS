#!/usr/bin/env bash
# Ubuntu STIG remediation wrapper: logs like rhel-stig/stig-remediate.sh and keeps
# the SCAP datastream under /var/log/stig-remediation for post-install oscap scans.
set -uo pipefail

LOG_DIR="/var/log/stig-remediation"
mkdir -p "$LOG_DIR"

DEBUG_LOG="$LOG_DIR/debug.log"
SUMMARY_LOG="$LOG_DIR/summary.log"

print_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_LOG"
}

log_exit_status() {
    local exit_code=$?
    local status_msg=""
    if [ "$exit_code" -eq 0 ]; then
        status_msg="SUCCESS"
    else
        status_msg="FAILED (exit code: $exit_code)"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Script execution $status_msg" >> "$SUMMARY_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Check $DEBUG_LOG for detailed logs" >> "$SUMMARY_LOG"
}

trap log_exit_status EXIT

REMEDIATION_SCRIPT="${STIG_REMEDIATION_SCRIPT:-/tmp/fix.sh}"

echo "Starting Ubuntu STIG remediation..."
print_debug "Starting Ubuntu STIG remediation..."
print_debug "Log directory: $LOG_DIR"

if [ ! -f "$REMEDIATION_SCRIPT" ]; then
    print_debug "ERROR: remediation script not found at $REMEDIATION_SCRIPT"
    echo "ERROR: remediation script not found at $REMEDIATION_SCRIPT" >&2
    echo "Check $DEBUG_LOG for details" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

ensure_oscap_and_content() {
    if command -v oscap >/dev/null 2>&1; then
        for p in \
            /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml \
            /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds-1.2.xml \
            /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml \
            /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds-1.2.xml \
            /usr/share/xml/scap/ssg/content/ssg-ubuntu2004-ds.xml \
            /usr/share/xml/scap/ssg/content/ssg-ubuntu2004-ds-1.2.xml
        do
            [ -f "$p" ] && return 0
        done
    fi
    print_debug "Installing openscap-scanner and scap-security-guide for datastream and oscap..."
    apt-get update || { print_debug "ERROR: apt-get update failed"; exit 1; }
    apt-get install -y --no-install-recommends openscap-scanner scap-security-guide \
        || { print_debug "ERROR: apt-get install (openscap / scap-security-guide) failed"; exit 1; }
}

ensure_oscap_and_content

STIG_XCCDF=""
for path in \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds-1.2.xml \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds-1.2.xml \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2004-ds.xml \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2004-ds-1.2.xml
do
    if [ -f "$path" ]; then
        STIG_XCCDF="$path"
        break
    fi
done

if [ -z "$STIG_XCCDF" ]; then
    print_debug "ERROR: STIG datastream (ssg-ubuntu*-ds.xml) not found after package install"
    echo "ERROR: STIG datastream not found under /usr/share/xml/scap/ssg/content/" >&2
    echo "Check $DEBUG_LOG for details" >&2
    exit 1
fi

STIG_PROFILE="xccdf_org.ssgproject.content_profile_stig"

echo "Using STIG datastream: $STIG_XCCDF"
echo "Using STIG profile: $STIG_PROFILE"
print_debug "Using STIG datastream: $STIG_XCCDF"
print_debug "Using STIG profile: $STIG_PROFILE"

STIG_DS_COPY="$LOG_DIR/$(basename "$STIG_XCCDF")"
cp "$STIG_XCCDF" "$STIG_DS_COPY"
print_debug "Copied STIG datastream to $STIG_DS_COPY for post-boot compliance scans"

if ! command -v oscap >/dev/null 2>&1; then
    print_debug "ERROR: oscap not found"
    echo "ERROR: oscap not found" >&2
    echo "Check $DEBUG_LOG for details" >&2
    exit 1
fi

REMEDIATION_LOG="$LOG_DIR/remediation.log"
print_debug "Running remediation script: $REMEDIATION_SCRIPT"
print_debug "Remediation log: $REMEDIATION_LOG"

set +e
bash -x "$REMEDIATION_SCRIPT" 2>&1 | tee "$REMEDIATION_LOG"
REMEDIATION_EXIT_CODE="${PIPESTATUS[0]}"
set -uo pipefail

if [ "$REMEDIATION_EXIT_CODE" -eq 0 ]; then
    print_debug "STIG remediation completed successfully"
else
    print_debug "STIG remediation completed with non-zero exit ($REMEDIATION_EXIT_CODE); see $REMEDIATION_LOG"
fi

REMEDIATION_SCRIPT_SAVED="$LOG_DIR/stig-fix.sh"
cp "$REMEDIATION_SCRIPT" "$REMEDIATION_SCRIPT_SAVED"
print_debug "Saved remediation script to $REMEDIATION_SCRIPT_SAVED"
chmod +r "$REMEDIATION_SCRIPT_SAVED" 2>/dev/null || true

print_debug "STIG remediation logs: $LOG_DIR"
print_debug "  $DEBUG_LOG (debug)"
print_debug "  $REMEDIATION_LOG (remediation stdout/stderr, bash -x)"
print_debug "  $STIG_DS_COPY (datastream for oscap xccdf eval on the host)"

exit 0
