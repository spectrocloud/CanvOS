#!/bin/bash
# Update static STIG content for Ubuntu 24.04
# Run this to pin STIG guide and remediation for reproducible releases.
# See README.md for release process and "latest STIG" options.
#
# Requires: cmake, make, openscap-utils, openscap-scanner, python3, pip, libxml2-utils, xsltproc
#   Ubuntu 24.04: apt install cmake make openscap-utils openscap-scanner python3 python3-pip libxml2-utils xsltproc

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_STIG_DIR="$(dirname "$SCRIPT_DIR")"
STATIC_DIR="$UBUNTU_STIG_DIR/static"
VERSION="${1:-}"
CONTENT_REPO="https://github.com/ComplianceAsCode/content"
PROFILE="xccdf_org.ssgproject.content_profile_stig"

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

# Build datastream from source - try ubuntu2404 first, fall back to ubuntu2204
echo "Building Ubuntu datastream (this may take a few minutes)..."
cd "$SRC_DIR"
pip3 install -q -r requirements.txt 2>/dev/null || true

XCCDF_FILE=""
for product in ubuntu2404 ubuntu2204; do
    if ./build_product "$product" -d 2>/dev/null; then
        XCCDF_PATH=$(find "$SRC_DIR/build" -name "ssg-${product}-ds*.xml" -type f | head -1)
        if [ -f "$XCCDF_PATH" ]; then
            XCCDF_FILE=$(basename "$XCCDF_PATH")
            break
        fi
    fi
done

if [ -z "$XCCDF_FILE" ] || [ ! -f "$SRC_DIR/build/$XCCDF_FILE" ]; then
    echo "ERROR: Build failed - could not find Ubuntu STIG datastream in $SRC_DIR/build"
    ls -la "$SRC_DIR/build" 2>/dev/null || true
    exit 1
fi

cp "$SRC_DIR/build/$XCCDF_FILE" "$STATIC_DIR/$XCCDF_FILE"
echo "Copied XCCDF to $STATIC_DIR/$XCCDF_FILE"

# Generate remediation script
if command -v oscap &>/dev/null; then
    echo "Generating remediation script..."
    oscap xccdf generate fix --profile "$PROFILE" --template urn:xccdf:fix:script:sh \
        "$STATIC_DIR/$XCCDF_FILE" > "$STATIC_DIR/stig-fix.sh" 2>/dev/null || true
    if [ -s "$STATIC_DIR/stig-fix.sh" ]; then
        chmod +x "$STATIC_DIR/stig-fix.sh"
        echo "Generated $STATIC_DIR/stig-fix.sh"
    else
        rm -f "$STATIC_DIR/stig-fix.sh"
        echo "WARNING: Could not generate remediation script. Use system packages as fallback."
    fi
else
    echo "WARNING: oscap not found. Install openscap-scanner to generate static remediation script."
fi

# Write VERSION file
echo "# STIG content version - pin for reproducible releases" > "$STATIC_DIR/VERSION"
echo "# Source: $CONTENT_REPO/releases" >> "$STATIC_DIR/VERSION"
echo "STIG_CONTENT_VERSION=$VERSION" >> "$STATIC_DIR/VERSION"

echo "Done. Static content updated to $VERSION"
