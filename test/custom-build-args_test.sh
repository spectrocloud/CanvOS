#!/bin/bash
# Unit tests for scripts/custom-build-args.sh (no Docker required).
#
# Each case runs inject_custom_build_args in a subshell against fixture
# Dockerfile / .arg files, so a guard's `exit 1` terminates only that subshell.
# The mutated Dockerfile is captured mid-run (before the restore trap fires on
# subshell exit) so injection can be asserted; the fixture is then checked to
# confirm it was restored byte-for-byte.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_ROOT/scripts/custom-build-args.sh"

PASS=0
FAIL=0

# run_case <name> <target> <dockerfile-content> <arg-content>
#   Sets globals: RC, MUTATED (Dockerfile content during the run),
#   RESTORED (Dockerfile content after the run), OUT (stdout+stderr).
run_case() {
    local name="$1" target="$2" dockerfile="$3" argfile="$4"
    local tmp; tmp="$(mktemp -d)"
    printf '%s\n' "$dockerfile" > "$tmp/Dockerfile"
    printf '%s\n' "$argfile"    > "$tmp/.arg"
    cp "$tmp/Dockerfile" "$tmp/Dockerfile.orig"

    OUT="$( (
        export CANVOS_DOCKERFILE="$tmp/Dockerfile"
        export CANVOS_ARG_FILE="$tmp/.arg"
        # shellcheck disable=SC1090,SC1091
        source "$LIB"
        # shellcheck disable=SC1090,SC1091
        source "$tmp/.arg"        # mimic earthly.sh `source .arg` (sets values)
        inject_custom_build_args "$target"
        cp "$CANVOS_DOCKERFILE" "$tmp/Dockerfile.mutated"   # capture mid-run state
    ) 2>&1 )"
    RC=$?

    MUTATED="$(cat "$tmp/Dockerfile.mutated" 2>/dev/null || true)"
    RESTORED="$(cat "$tmp/Dockerfile")"
    ORIG="$(cat "$tmp/Dockerfile.orig")"
    BAK_EXISTS=no; [ -f "$tmp/Dockerfile.canvos.bak" ] && BAK_EXISTS=yes
    LAST_CASE="$name"
    rm -rf "$tmp"
}

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n    %s\n' "$LAST_CASE" "$1"; }

expect_rc()       { [ "$RC" -eq "$1" ] || bad "expected rc=$1 got rc=$RC (out: $OUT)"; }
mutated_has()     { printf '%s' "$MUTATED"  | grep -qF "$1" || bad "mutated Dockerfile missing: $1"; }
restored_equals() { [ "$RESTORED" = "$ORIG" ] || bad "Dockerfile not restored to original"; }
out_has()         { printf '%s' "$OUT" | grep -qF "$1" || bad "output missing: $1 (out: $OUT)"; }
bak_gone()        { [ "$BAK_EXISTS" = no ] || bad "backup file was left behind"; }

# 1. Inject into a bare ARG.
run_case "inject bare ARG" "+iso" "ARG BRAND" "CUSTOM_ARG_BRAND=acme"
expect_rc 0; mutated_has "ARG BRAND=acme"; restored_equals; bak_gone
[ "$FAIL" -eq 0 ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 2. Override an existing default.
run_case "override default" "+iso" "ARG DHCP_VENDOR_CLASS=default-class" "CUSTOM_ARG_DHCP_VENDOR_CLASS=retail"
expect_rc 0; mutated_has "ARG DHCP_VENDOR_CLASS=retail"; restored_equals
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 3. Typo: CUSTOM_ARG with no matching ARG -> ERROR.
run_case "typo -> error" "+iso" "ARG BRAND" "CUSTOM_ARG_BRAN=acme"
expect_rc 1; out_has "no 'ARG BRAN'"; restored_equals
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 4. Reserved / Earthfile-managed name -> ERROR.
run_case "reserved -> error" "+iso" "ARG BRAND" "CUSTOM_ARG_OS_DISTRIBUTION=rhel"
expect_rc 1; out_has "managed by CanvOS/Earthfile"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 4b. Reserved template knob (IS_UKI) -> ERROR even if declared in Dockerfile.
run_case "reserved IS_UKI -> error" "+iso" "ARG IS_UKI" "CUSTOM_ARG_IS_UKI=true"
expect_rc 1; out_has "managed by CanvOS/Earthfile"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 4c. Reserved template knob (CUSTOM_TAG) -> ERROR.
run_case "reserved CUSTOM_TAG -> error" "+iso" "ARG CUSTOM_TAG" "CUSTOM_ARG_CUSTOM_TAG=foo"
expect_rc 1; out_has "managed by CanvOS/Earthfile"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 5. Empty value -> ERROR.
run_case "empty value -> error" "+iso" "ARG BRAND" "CUSTOM_ARG_BRAND="
expect_rc 1; out_has "set but empty"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 6. Normal Earthfile .arg keys must NOT false-positive.
run_case "earthfile keys ignored" "+iso" "ARG BRAND=foo" "$(printf 'CUSTOM_TAG=demo\nIMAGE_REGISTRY=ttl.sh\nOS_DISTRIBUTION=ubuntu')"
expect_rc 0; restored_equals
printf '%s' "$OUT" | grep -qiE 'ERROR' && bad "false-positive error on normal .arg keys"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 7. Guard 6: unsatisfied bare ARG on an image target -> ERROR.
run_case "unsatisfied ARG on image target" "+iso" "ARG BRAND" ""
expect_rc 1; out_has "Refusing to build it silently empty"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 8. Guard 6b: same on a non-Dockerfile target -> WARNING, proceeds.
run_case "unsatisfied ARG on util target" "+go-deps" "ARG BRAND" ""
expect_rc 0; out_has "WARNING"
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

# 9. Value with sed metacharacters (/ and &) is injected verbatim. Quoted in
#    .arg so it survives being sourced (CanvOS sources .arg).
run_case "value with metachars" "+iso" "ARG REGISTRYPATH" 'CUSTOM_ARG_REGISTRYPATH="reg.io/a&b"'
expect_rc 0; mutated_has "ARG REGISTRYPATH=reg.io/a&b"; restored_equals
[ "$FAIL" -eq "$FAIL_AT" ] && ok "$LAST_CASE"; FAIL_AT=$FAIL

echo "----------------------------------------"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
