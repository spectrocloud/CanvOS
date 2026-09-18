#!/bin/bash
# The script runs under Earthly `RUN --secret`; whatever it prints lands in build logs (CWE-532).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ACCESS_KEY_MARKER="AKIA_CANVOS_XTRACE_MARKER"
SECRET_KEY_MARKER="CANVOS_SECRET_XTRACE_MARKER"
SESSION_TOKEN_MARKER="CANVOS_SESSION_XTRACE_MARKER"

mkdir -p "$WORK_DIR/bin"
for cmd in curl jq aws; do
  printf '#!/bin/sh\nexit 0\n' > "$WORK_DIR/bin/$cmd"
  chmod +x "$WORK_DIR/bin/$cmd"
done

set +e
output=$(
  cd "$WORK_DIR" \
  && PATH="$WORK_DIR/bin:$PATH" \
     REGION=us-east-1 \
     S3_BUCKET=bucket \
     S3_KEY=key \
     AWS_ACCESS_KEY_ID="$ACCESS_KEY_MARKER" \
     AWS_SECRET_ACCESS_KEY="$SECRET_KEY_MARKER" \
     AWS_SESSION_TOKEN="$SESSION_TOKEN_MARKER" \
     bash "$SCRIPT_DIR/create-raw-to-ami.sh" "$WORK_DIR/absent.raw" 2>&1
)
set -e

# Guards against a vacuous pass: if the script stops reaching the credential
# block, it leaks nothing and every marker check below trivially succeeds.
if ! printf '%s' "$output" | grep -qF 'Using AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY'; then
  echo "FAIL: script never reached credential handling; this test no longer proves anything" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

status=0
for marker in "$ACCESS_KEY_MARKER" "$SECRET_KEY_MARKER" "$SESSION_TOKEN_MARKER"; do
  if printf '%s' "$output" | grep -qF "$marker"; then
    echo "FAIL: credential value '$marker' leaked into script output" >&2
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  echo "--- captured output ---" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "PASS: no credential values in script output"
