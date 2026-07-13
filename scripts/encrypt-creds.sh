#!/usr/bin/env bash
# encrypt-creds.sh — encrypt release credentials for the base-images workflow.
#
# What this does:
#   - Prompts (silently) for RHSM username, RHSM password, Ubuntu Pro token
#   - Encrypts each with age using the repo's team.age.pub
#   - Base64-encodes the ciphertext so it fits on one line
#   - Prints copy-pasteable blocks for the workflow_dispatch form
#
# What this NEVER does:
#   - Echo your plaintext credentials to the terminal
#   - Write plaintext credentials to any file
#   - Send anything over the network
#
# Requirements:
#   - `age` v1.x  (brew install age  |  apt install age  |  https://age-encryption.org)
#   - `base64`    (BSD or GNU — the script handles both)
#
# Usage:
#   scripts/encrypt-creds.sh
#
# Leave any prompt blank if you don't need that family (e.g. no Ubuntu FIPS →
# leave the Pro token blank).

set -euo pipefail

# Do NOT enable `set -x` — that would echo values.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
pubkey_file="$repo_root/team.age.pub"

if ! command -v age >/dev/null 2>&1; then
    echo "error: 'age' not installed. Install with 'brew install age' or see https://age-encryption.org" >&2
    exit 1
fi

if [ ! -f "$pubkey_file" ]; then
    echo "error: $pubkey_file not found. Run this script from a clean checkout." >&2
    exit 1
fi

pubkey="$(grep -oE 'age1[a-z0-9]+' "$pubkey_file" | head -1)"
if [ -z "$pubkey" ]; then
    echo "error: could not parse a public key from $pubkey_file" >&2
    exit 1
fi

# base64 -w0 on GNU, `base64` on BSD does not wrap by default → normalize.
b64_flat() {
    if base64 --help 2>&1 | grep -q -- '-w'; then
        base64 -w0
    else
        base64 | tr -d '\n'
    fi
}

encrypt_one() {
    # Read stdin, encrypt with age (binary), base64-encode single-line.
    # NOTE: `age -r <pubkey>` reads plaintext from stdin, writes binary
    # ciphertext to stdout. base64 turns it into a paste-safe string.
    age -r "$pubkey" | b64_flat
}

echo "This will encrypt each credential using $pubkey_file"
echo "Leave a prompt blank to skip that credential."
echo

# `read -s` hides typed input. Trailing echo restores the newline.
IFS= read -r -s -p "RHSM username: " rhsm_user;  echo
IFS= read -r -s -p "RHSM password: " rhsm_pass;  echo
IFS= read -r -s -p "Ubuntu Pro token: " ubuntu_pro; echo

enc_rhsm_user=""
enc_rhsm_pass=""
enc_ubuntu_pro=""

if [ -n "$rhsm_user" ]; then
    enc_rhsm_user="$(printf '%s' "$rhsm_user" | encrypt_one)"
fi
if [ -n "$rhsm_pass" ]; then
    enc_rhsm_pass="$(printf '%s' "$rhsm_pass" | encrypt_one)"
fi
if [ -n "$ubuntu_pro" ]; then
    enc_ubuntu_pro="$(printf '%s' "$ubuntu_pro" | encrypt_one)"
fi

# Zero-out the plaintext vars as soon as possible.
unset rhsm_user rhsm_pass ubuntu_pro

echo
echo "════════════════════════════════════════════════════════════════════"
echo "  Copy each non-empty block below into the workflow_dispatch form."
echo "  Blank blocks = skip that credential (the workflow will skip the"
echo "  corresponding image family)."
echo "════════════════════════════════════════════════════════════════════"
echo
printf '─── rhel_subscription_username_encrypted ───\n%s\n\n' "$enc_rhsm_user"
printf '─── rhel_subscription_password_encrypted ───\n%s\n\n' "$enc_rhsm_pass"
printf '─── ubuntu_pro_token_encrypted ───\n%s\n\n' "$enc_ubuntu_pro"
