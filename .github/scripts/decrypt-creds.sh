#!/usr/bin/env bash
# decrypt-creds.sh — runs inside the extensions job of base-images.yaml.
#
# Reads three ciphertext env vars (safe to have in `env:` because ciphertext
# is useless without the private key) and the private key (from a repo secret,
# so GitHub Actions has already added it to the mask set). Decrypts each,
# calls ::add-mask:: on the plaintext BEFORE any subsequent step can log it,
# and exports the plaintext to $GITHUB_ENV.
#
# Invariants — do not break:
#   - Never `set -x`
#   - Never `echo` a plaintext value
#   - Never write plaintext to a file other than $GITHUB_ENV (post-mask)
#   - Wipe the private key file on exit
#
# Inputs (env vars, set by the workflow step):
#   RHEL_USER_CIPHER    base64(age(username))       may be empty
#   RHEL_PASS_CIPHER    base64(age(password))       may be empty
#   PRO_TOKEN_CIPHER    base64(age(ubuntu pro))     may be empty
#   DECRYPT_KEY         age private key (masked)    required if any cipher is non-empty
#
# Outputs (via $GITHUB_ENV):
#   RHSM_USER           (if RHEL_USER_CIPHER provided)
#   RHSM_PASS           (if RHEL_PASS_CIPHER provided)
#   UBUNTU_PRO_TOKEN    (if PRO_TOKEN_CIPHER provided)

set -euo pipefail

: "${GITHUB_ENV:?}"

any_cipher="${RHEL_USER_CIPHER:-}${RHEL_PASS_CIPHER:-}${PRO_TOKEN_CIPHER:-}"
if [ -z "$any_cipher" ]; then
    echo "No ciphertext inputs supplied — nothing to decrypt."
    exit 0
fi

if [ -z "${DECRYPT_KEY:-}" ]; then
    echo "::error::DECRYPT_KEY is empty — set the WORKFLOW_DECRYPT_KEY repo secret to the age private key."
    exit 1
fi

if ! command -v age >/dev/null 2>&1; then
    echo "::error::age is not installed on this runner. Add a setup step before Decrypt credentials."
    exit 1
fi

# Write the private key to a per-process file with restricted permissions.
# Trap wipes it on exit (success or failure).
key_file="$(mktemp)"
chmod 600 "$key_file"
trap 'shred -u "$key_file" 2>/dev/null || rm -f "$key_file"' EXIT
printf '%s' "$DECRYPT_KEY" > "$key_file"

decrypt_one() {
    # Args: $1 = base64(age(plaintext))
    # Reads plaintext to stdout. Never echoes the input.
    printf '%s' "$1" | base64 -d 2>/dev/null | age --decrypt -i "$key_file"
}

mask_and_export() {
    # Args: $1 = env var name, $2 = plaintext value
    # Order matters: ::add-mask:: must run BEFORE the value ever reaches
    # $GITHUB_ENV, because GitHub reads $GITHUB_ENV into the process env
    # for subsequent steps and any step that lists this var in its `env:`
    # block would otherwise get the plaintext dumped.
    local name="$1" value="$2"
    if [ -z "$value" ]; then
        # Empty decrypt result is treated as "nothing to export" — do NOT
        # write an empty env line (that would blank out any inherited value).
        echo "::warning::$name decrypted to empty string — skipping export"
        return 0
    fi
    # ::add-mask:: line is intercepted by the runner; the value is not
    # written to the log.
    printf '::add-mask::%s\n' "$value"
    # Single-line assignment (no here-doc). RHSM usernames/passwords and
    # Ubuntu Pro tokens are single-line values by nature.
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
}

if [ -n "${RHEL_USER_CIPHER:-}" ]; then
    plain="$(decrypt_one "$RHEL_USER_CIPHER")"
    mask_and_export "RHSM_USER" "$plain"
    unset plain
fi

if [ -n "${RHEL_PASS_CIPHER:-}" ]; then
    plain="$(decrypt_one "$RHEL_PASS_CIPHER")"
    mask_and_export "RHSM_PASS" "$plain"
    unset plain
fi

if [ -n "${PRO_TOKEN_CIPHER:-}" ]; then
    plain="$(decrypt_one "$PRO_TOKEN_CIPHER")"
    mask_and_export "UBUNTU_PRO_TOKEN" "$plain"
    unset plain
fi

echo "Credentials decrypted, masked, and exported to \$GITHUB_ENV (values not shown)."
