#!/bin/bash
# custom-build-args.sh
#
# Pass custom Docker build arguments into the user Dockerfile in CanvOS.
#
# WHY THIS EXISTS
#   The Earthfile's base-image target forwards only a FIXED --build-arg list
#   into ./Dockerfile (BASE, OS_*, proxies, DRBD_VERSION), and Earthly's
#   `FROM DOCKERFILE` cannot forward build args dynamically. So any custom
#   `ARG` a user adds to ./Dockerfile never receives a value from .arg and
#   silently resolves to its default -- with no build-time indication. That
#   silent drop is the bug this file fixes.
#
# HOW TO USE
#   Declare the value in .arg with the CUSTOM_ARG_ prefix, and declare the
#   matching ARG in ./Dockerfile:
#
#     # .arg
#     CUSTOM_ARG_BRAND=acme
#     CUSTOM_ARG_DHCP_VENDOR_CLASS=retail
#
#     # Dockerfile
#     ARG BRAND
#     ARG DHCP_VENDOR_CLASS=default-class
#
#   Before Earthly runs, inject_custom_build_args() rewrites each matching
#   `ARG NAME` line so its default becomes the requested value. The upstream
#   Earthfile is NEVER modified; the original Dockerfile is restored on exit.
#
#   Do NOT pass secrets this way -- build args leak into `docker history` and
#   the build cache. Use the UBUNTU_PRO_KEY / --secret flow instead.
#
# FAIL-CLOSED GUARDS (every failure is loud -- the opposite of the old bug)
#   1. CUSTOM_ARG_<NAME> with no `ARG <NAME>` in the Dockerfile -> ERROR (typo)
#   2. CUSTOM_ARG_<NAME> where NAME is Earthfile-managed        -> ERROR
#   3. CUSTOM_ARG_<NAME> with an empty value                    -> ERROR
#   4. injection did not take effect                            -> ERROR
#   5. no Dockerfile present                                    -> skip cleanly
#   6. a custom ARG with no default AND no value, on an
#      image/iso build target                                   -> ERROR
#      (same case on a non-Dockerfile target                    -> WARNING)
#
# TESTABILITY
#   Override CANVOS_DOCKERFILE and CANVOS_ARG_FILE to point at fixtures. See
#   test/custom-build-args_test.sh.

# Args the Earthfile already forwards into the Dockerfile; not user-custom.
CANVOS_RESERVED_ARGS="${CANVOS_RESERVED_ARGS:-BASE OS_DISTRIBUTION OS_VERSION HTTP_PROXY HTTPS_PROXY NO_PROXY DRBD_VERSION PROXY_CERT_PATH}"

CANVOS_DOCKERFILE="${CANVOS_DOCKERFILE:-./Dockerfile}"
CANVOS_ARG_FILE="${CANVOS_ARG_FILE:-.arg}"
CANVOS_DOCKERFILE_BACKUP=""

restore_dockerfile() {
    if [ -n "$CANVOS_DOCKERFILE_BACKUP" ] && [ -f "$CANVOS_DOCKERFILE_BACKUP" ]; then
        mv -f "$CANVOS_DOCKERFILE_BACKUP" "$CANVOS_DOCKERFILE"
        CANVOS_DOCKERFILE_BACKUP=""
    fi
}

# Is $1 a target that actually builds the Dockerfile? Every image/iso target
# pulls +base-image (which does `FROM DOCKERFILE`); utility targets (+go-deps,
# +uki-genkey, ...) do not.
is_dockerfile_target() {
    case "$1" in
        +*image*|+*iso*) return 0 ;;
        *) return 1 ;;
    esac
}

is_reserved_arg() {
    local name="$1" r
    for r in $CANVOS_RESERVED_ARGS; do
        [ "$name" = "$r" ] && return 0
    done
    return 1
}

# ARG names declared in the Dockerfile, one per line.
dockerfile_arg_names() {
    grep -oE '^[[:space:]]*ARG[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$CANVOS_DOCKERFILE" | awk '{print $2}'
}

# Does the Dockerfile declare `ARG NAME` with an inline default (`ARG NAME=`)?
dockerfile_arg_has_default() {
    grep -qE "^[[:space:]]*ARG[[:space:]]+$1[[:space:]]*=" "$CANVOS_DOCKERFILE"
}

# CUSTOM_ARG_* keys declared in the .arg file, one per line.
custom_arg_keys() {
    [ -f "$CANVOS_ARG_FILE" ] || return 0
    grep -oE '^[[:space:]]*CUSTOM_ARG_[A-Za-z0-9_]+=' "$CANVOS_ARG_FILE" 2>/dev/null \
        | sed -E 's/^[[:space:]]*//; s/=$//'
}

inject_custom_build_args() {
    local target="${1:-}"

    # Guard 5: no Dockerfile -> nothing to do.
    [ -f "$CANVOS_DOCKERFILE" ] || return 0

    local dockerfile_args
    dockerfile_args="$(dockerfile_arg_names)"

    local injected=() defaulted=() key name value esc

    # Validate + inject every CUSTOM_ARG_* declared in .arg (guards 1-4).
    # Keys come from the .arg file; values come from the sourced env (so any
    # `$VAR` references in .arg are already resolved by the time we run).
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        name="${key#CUSTOM_ARG_}"
        value="${!key-}"

        # Guard 2: reserved / Earthfile-managed name.
        if is_reserved_arg "$name"; then
            echo >&2 "ERROR: $key targets '$name', which is managed by CanvOS/Earthfile."
            echo >&2 "       Set it via its normal .arg key ($name=...), not $key."
            exit 1
        fi
        # Guard 1: no matching ARG in the Dockerfile (typo / not declared).
        if ! printf '%s\n' "$dockerfile_args" | grep -qxF "$name"; then
            echo >&2 "ERROR: $key is set in .arg but the Dockerfile has no 'ARG $name'."
            echo >&2 "       Check for a typo, or add 'ARG $name' to the Dockerfile."
            exit 1
        fi
        # Guard 3: empty value.
        if [ -z "$value" ]; then
            echo >&2 "ERROR: $key is set but empty. Give it a value, or drop it and use"
            echo >&2 "       an inline default in the Dockerfile ('ARG $name=...')."
            exit 1
        fi

        # Back up the Dockerfile once, and arm the restore trap.
        if [ -z "$CANVOS_DOCKERFILE_BACKUP" ]; then
            CANVOS_DOCKERFILE_BACKUP="${CANVOS_DOCKERFILE}.canvos.bak"
            cp "$CANVOS_DOCKERFILE" "$CANVOS_DOCKERFILE_BACKUP"
            trap restore_dockerfile EXIT INT TERM
        fi

        # Escape sed replacement metacharacters (\ & /) in the value.
        esc="$(printf '%s' "$value" | sed -e 's/[\/&\\]/\\&/g')"
        # `ARG NAME` or `ARG NAME=old`  ->  `ARG NAME=<value>` (all occurrences).
        sed -i -E "s|^([[:space:]]*ARG[[:space:]]+${name})([[:space:]]*=.*)?[[:space:]]*\$|\\1=${esc}|" "$CANVOS_DOCKERFILE"

        # Guard 4: confirm the rewrite took effect. A tool built to kill silent
        # failure must not fail silently itself.
        if ! grep -qE "^[[:space:]]*ARG[[:space:]]+${name}[[:space:]]*=" "$CANVOS_DOCKERFILE"; then
            echo >&2 "ERROR: failed to inject a value for '$name' into the Dockerfile."
            exit 1
        fi
        injected+=("$name=$value")
    done < <(custom_arg_keys)

    # Guard 6: a custom ARG declared in the Dockerfile but never satisfied
    # (no CUSTOM_ARG_ value AND no inline default) would build empty -- the
    # exact silent failure that caused this incident.
    local a i was_injected
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        is_reserved_arg "$a" && continue
        was_injected=false
        for i in "${injected[@]}"; do
            [ "${i%%=*}" = "$a" ] && { was_injected=true; break; }
        done
        $was_injected && continue
        if dockerfile_arg_has_default "$a"; then
            defaulted+=("$a")
            continue
        fi
        if is_dockerfile_target "$target"; then
            echo >&2 "ERROR: the Dockerfile declares 'ARG $a' with no default and no value"
            echo >&2 "       was provided. Set CUSTOM_ARG_$a in .arg, or give it a default"
            echo >&2 "       ('ARG $a=...'). Refusing to build it silently empty."
            exit 1
        else
            echo >&2 "WARNING: the Dockerfile declares 'ARG $a' with no default and no value;"
            echo >&2 "         target '$target' does not build the Dockerfile -- continuing."
        fi
    done < <(printf '%s\n' "$dockerfile_args")

    # Report what happened -- fixes the original "no build-time indication".
    if [ ${#injected[@]} -gt 0 ] || [ ${#defaulted[@]} -gt 0 ]; then
        echo "Custom Docker build args:"
        [ ${#injected[@]} -gt 0 ]  && echo "  injected:        ${injected[*]}"
        [ ${#defaulted[@]} -gt 0 ] && echo "  left at default: ${defaulted[*]}"
    fi
}
