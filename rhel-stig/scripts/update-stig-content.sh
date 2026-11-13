#!/bin/bash
# Update static STIG content for RHEL 9
# Run this to pin STIG guide and remediation for reproducible releases.
# See README.md for release process and "latest STIG" options.
#
# Requires: cmake, make, openscap-utils, openscap-scanner, python3, pip
#   RHEL/Fedora: dnf install cmake make openscap-utils openscap-scanner python3 python3-pip
#   Ubuntu: apt install cmake make libopenscap8 openscap-utils openscap-scanner python3 python3-pip

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RHEL_STIG_DIR="$(dirname "$SCRIPT_DIR")"
STATIC_DIR="$RHEL_STIG_DIR/static"
VERSION="${1:-}"
CONTENT_REPO="https://github.com/ComplianceAsCode/content"
PROFILE="xccdf_org.ssgproject.content_profile_stig_pe9043"
TAILORING_FILE="$STATIC_DIR/pe9043-tailoring.xml"
XCCDF_FILE="ssg-rhel9-ds.xml"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.1.79"
    echo "Releases: $CONTENT_REPO/releases"
    exit 1
fi

mkdir -p "$STATIC_DIR"
WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

echo "Downloading scap-security-guide $VERSION..."
TARBALL="$WORK_DIR/scap-security-guide-${VERSION#v}.tar.bz2"
URL="$CONTENT_REPO/releases/download/$VERSION/scap-security-guide-${VERSION#v}.tar.bz2"
curl -sSL -o "$TARBALL" "$URL" || { echo "Failed to download $URL"; exit 1; }

echo "Extracting..."
tar -xjf "$TARBALL" -C "$WORK_DIR"
SRC_DIR="$WORK_DIR/scap-security-guide-${VERSION#v}"
rm -f "$TARBALL"

if [ ! -d "$SRC_DIR" ]; then
    echo "ERROR: Expected directory $SRC_DIR not found"
    ls -la "$WORK_DIR"
    exit 1
fi

# Build datastream from source (release tarball contains source, not pre-built)
echo "Building RHEL 9 datastream (this may take a few minutes)..."
cd "$SRC_DIR"
pip3 install -q -r requirements.txt 2>/dev/null || true
./build_product rhel9 -d || true

XCCDF_PATH="$SRC_DIR/build/$XCCDF_FILE"
if [ ! -f "$XCCDF_PATH" ]; then
    XCCDF_PATH=$(find "$SRC_DIR/build" -name "ssg-rhel9-ds*.xml" -type f | head -1)
fi
if [ ! -f "$XCCDF_PATH" ]; then
    echo "ERROR: Build failed - could not find $XCCDF_FILE in $SRC_DIR/build"
    ls -la "$SRC_DIR/build" 2>/dev/null || true
    exit 1
fi

cp "$XCCDF_PATH" "$STATIC_DIR/$XCCDF_FILE"
echo "Copied XCCDF to $STATIC_DIR/$XCCDF_FILE"

# Generate remediation script
if ! command -v oscap &>/dev/null; then
    echo "ERROR: oscap not found. Install openscap-scanner to generate the static remediation script."
    exit 1
fi
if [ ! -f "$TAILORING_FILE" ]; then
    echo "ERROR: tailoring file not found: $TAILORING_FILE"
    exit 1
fi

echo "Generating remediation script (profile $PROFILE, tailoring $TAILORING_FILE)..."
if ! oscap xccdf generate fix \
    --profile "$PROFILE" \
    --tailoring-file "$TAILORING_FILE" \
    --template urn:xccdf:fix:script:sh \
    "$STATIC_DIR/$XCCDF_FILE" > "$STATIC_DIR/stig-fix.sh" 2>/dev/null; then
    rm -f "$STATIC_DIR/stig-fix.sh"
    echo "ERROR: oscap failed to generate $STATIC_DIR/stig-fix.sh"
    exit 1
fi
if [ ! -s "$STATIC_DIR/stig-fix.sh" ]; then
    rm -f "$STATIC_DIR/stig-fix.sh"
    echo "ERROR: generated $STATIC_DIR/stig-fix.sh is empty"
    exit 1
fi
chmod +x "$STATIC_DIR/stig-fix.sh"
echo "Generated $STATIC_DIR/stig-fix.sh"

# Write VERSION file
echo "# STIG content version - pin for reproducible releases" > "$STATIC_DIR/VERSION"
echo "# Source: $CONTENT_REPO/releases" >> "$STATIC_DIR/VERSION"
echo "STIG_CONTENT_VERSION=$VERSION" >> "$STATIC_DIR/VERSION"

echo "Done. Static content updated to $VERSION"

