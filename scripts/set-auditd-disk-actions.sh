#!/usr/bin/env bash
# PE-9043: make auditd's disk-space actions non-halting.
#
# A full audit partition must not take the node down. disk_full_action and
# disk_error_action accept SYSLOG, SINGLE or HALT, so SYSLOG keeps the node up;
# admin_space_left_action has to stay single to satisfy the STIG rule.
#
# Run this AFTER any STIG remediation: regenerated content can reintroduce HALT.
# It is a no-op when auditd is not installed (no /etc/audit/auditd.conf).
#
# Usage: set-auditd-disk-actions.sh [auditd.conf]
set -uo pipefail

conf="${1:-/etc/audit/auditd.conf}"

if [ ! -f "$conf" ]; then
    echo "PE-9043: $conf not present; auditd disk-space actions not applicable"
    exit 0
fi

status=0

set_key() {
    local key="$1" value="$2"
    if grep -qiE "^[[:space:]]*${key}[[:space:]]*=" "$conf"; then
        if ! sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|I" "$conf"; then
            echo "PE-9043: failed to set ${key} in ${conf}" >&2
            status=1
        fi
    elif ! printf '%s = %s\n' "$key" "$value" >> "$conf"; then
        echo "PE-9043: failed to append ${key} to ${conf}" >&2
        status=1
    fi
}

set_key disk_full_action SYSLOG
set_key disk_error_action SYSLOG
set_key admin_space_left_action single

if [ "$status" -eq 0 ]; then
    echo "PE-9043: auditd disk-space actions set in ${conf}"
fi

exit "$status"
