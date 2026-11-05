#!/usr/bin/env bash
# PE-9043: regenerate the Ubuntu FIPS STIG remediation with the auditd
# disk-space values (disk_full_action/disk_error_action -> syslog,
# admin_space_left_action -> single).
#
# 22.04's exact 0.1.67 STIG datastream is not published upstream: 0.1.67 has no
# STIG profile (only CIS/standard), and Canonical's STIG content is not
# published as a datastream. 0.1.78 is the closest available with the STIG
# profile and all three auditd rules, so it is used for both 22.04 and 24.04.
set -euo pipefail
cd "$(dirname "$0")/.."
VER=0.1.78
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/ComplianceAsCode/content/releases/download/v${VER}/scap-security-guide-${VER}.tar.gz" -o "$TMP/ssg.tgz"
tar -xzf "$TMP/ssg.tgz" -C "$TMP"
SRC="$TMP/scap-security-guide-${VER}"
for v in 22.04 24.04; do
  cp "$v/pe9043-tailoring.xml" "$SRC/"
  oscap xccdf generate fix --profile xccdf_org.ssgproject.content_profile_stig_pe9043 --tailoring-file "$SRC/pe9043-tailoring.xml" --template urn:xccdf:fix:script:sh "$SRC/ssg-ubuntu${v//./}-ds.xml" > "$v/fix.sh"
  chmod +x "$v/fix.sh"
  python3 "$(dirname "$0")/postprocess-fix.py" "$v/fix.sh"
  echo "regenerated $v/fix.sh"
done
