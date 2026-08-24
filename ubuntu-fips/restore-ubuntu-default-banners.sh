#!/usr/bin/env bash
# Restore distribution-default login banners after STIG remediation.
# Removes USG / DoD banner text from issue files, SSH, profile.d, and GDM (if present)
# while leaving other STIG settings intact.

set -e

if [ -r /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  label="${PRETTY_NAME:-Ubuntu}"
else
  label="Ubuntu"
fi

printf '%s \\n \\l\n' "$label" > /etc/issue
printf '%s\n' "$label" > /etc/issue.net

rm -f /etc/profile.d/ssh_confirm.sh

if [ -f /etc/ssh/sshd_config ]; then
  sed -i '/^[[:space:]]*Banner[[:space:]]/d' /etc/ssh/sshd_config
fi
if [ -d /etc/ssh/sshd_config.d ]; then
  shopt -s nullglob
  for f in /etc/ssh/sshd_config.d/*.conf; do
    sed -i '/^[[:space:]]*Banner[[:space:]]/d' "$f"
  done
  shopt -u nullglob
fi

if [ -f /etc/gdm3/greeter.dconf-defaults ]; then
  sed -i '/^[[:space:]]*banner-message-enable/d; /^[[:space:]]*banner-message-text/d' \
    /etc/gdm3/greeter.dconf-defaults
fi

shopt -s nullglob
for f in /etc/dconf/db/gdm.d/00-security-settings /etc/dconf/db/local.d/*; do
  [ -f "$f" ] || continue
  if grep -q 'banner-message' "$f" 2>/dev/null; then
    sed -i '/banner-message-enable/d; /banner-message-text/d' "$f"
  fi
done
lock=/etc/dconf/db/gdm.d/locks/00-security-settings-lock
if [ -f "$lock" ] && grep -q 'banner-message' "$lock" 2>/dev/null; then
  sed -i '/banner-message-enable/d; /banner-message-text/d' "$lock"
fi
shopt -u nullglob

if command -v dconf >/dev/null 2>&1; then
  (umask 0022 && dconf update) || true
fi
