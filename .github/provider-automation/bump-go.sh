#!/usr/bin/env bash
#
# bump-go.sh <go_version>
#
# Updates every Go-version reference in the CURRENT working directory (a
# checked-out provider repo) to <go_version>. Idempotent and tolerant of
# repos that lack some files. Prints the files it changed.
#
#   go.mod                       ->  go <X.Y.Z>            (language/toolchain directive)
#   Earthfile                    ->  ARG GOLANG_VERSION=<X.Y.Z>
#   Dockerfile                   ->  FROM golang:<X.Y.Z>-alpine ...
#   .github/workflows/*.y*ml     ->  go-version: '<X.Y.Z>'  (literal pins only; leaves go-version-file alone)
#
set -euo pipefail

VER="${1:?usage: bump-go.sh <go_version>}"
# Accept "1.26.4" or "go1.26.4"; normalise to bare semver.
VER="${VER#go}"
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "::error::invalid go version '$VER' (expected e.g. 1.26.4)" >&2
  exit 2
fi

changed=()

bump() { # file  sed-expr
  local f="$1" expr="$2"
  [[ -f "$f" ]] || return 0
  local before; before="$(cat "$f")"
  # macOS/BSD vs GNU sed in-place compatibility
  if sed --version >/dev/null 2>&1; then sed -i -E "$expr" "$f"; else sed -i '' -E "$expr" "$f"; fi
  [[ "$before" != "$(cat "$f")" ]] && changed+=("$f") || true
}

# go.mod: the bare "go X.Y[.Z]" directive (not "toolchain go...").
bump "go.mod" "s/^go [0-9]+(\.[0-9]+){1,2}$/go ${VER}/"

# Earthfile: ARG GOLANG_VERSION=...
bump "Earthfile" "s/^([[:space:]]*ARG[[:space:]]+GOLANG_VERSION=)[0-9]+(\.[0-9]+){1,2}/\1${VER}/"

# Dockerfile: FROM golang:<ver>-alpine (any stage alias suffix preserved).
bump "Dockerfile" "s/(FROM[[:space:]]+golang:)[0-9]+(\.[0-9]+){0,2}(-alpine)/\1${VER}\3/"

# Workflow literal go-version pins (skip go-version-file).
if [[ -d .github/workflows ]]; then
  while IFS= read -r -d '' wf; do
    bump "$wf" "s/(go-version:[[:space:]]*')[0-9]+(\.[0-9]+){0,2}(')/\1${VER}\3/"
  done < <(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "no-op: already on Go ${VER} (or no recognised version references)"
else
  printf 'updated to Go %s:\n' "$VER"
  printf '  - %s\n' "${changed[@]}"
fi
