#!/usr/bin/env bash
# PE-9043: regenerate the pinned STIG remediation from the datastream.
# The tailoring refines only disk_full_action/disk_error_action to syslog
# (STIG-accepted); admin_space_left_action stays single.
set -euo pipefail
cd "$(dirname "$0")/.."
oscap xccdf generate fix \
  --profile xccdf_org.ssgproject.content_profile_stig_pe9043 \
  --tailoring-file static/pe9043-tailoring.xml \
  --template urn:xccdf:fix:script:sh \
  static/ssg-rhel9-ds.xml > static/stig-fix.sh
chmod +x static/stig-fix.sh
echo "regenerated static/stig-fix.sh"
