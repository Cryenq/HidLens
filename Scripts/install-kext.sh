#!/bin/bash
# HidLens KEXT installer
# Usage: sudo ./Scripts/install-kext.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEXT_SRC="$PROJECT_DIR/build/Debug/HidLensDriver.kext"
KEXT_DST="/tmp/HidLensDriver.kext"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

if [ ! -d "$KEXT_SRC" ]; then
    echo "Error: KEXT not found at $KEXT_SRC"
    echo "Build the KEXT first: xcodebuild -target HidLensDriver -configuration Debug build"
    exit 1
fi

# Unload if already loaded
if kextstat 2>/dev/null | grep -q "com.hidlens.driver"; then
    echo "Unloading existing HidLensDriver..."
    kextunload -b com.hidlens.driver 2>/dev/null || true
fi

# Clear kernel extension staging cache
echo "Clearing staging cache..."
rm -rf /private/var/db/KernelExtensionManagement/Staging/com.hidlens.driver.* 2>/dev/null || true

# Copy to /tmp and fix ownership (KEXTs require root:wheel)
echo "Preparing KEXT..."
rm -rf "$KEXT_DST"
cp -R "$KEXT_SRC" "$KEXT_DST"
chown -R root:wheel "$KEXT_DST"
chmod -R 755 "$KEXT_DST"

# Re-sign with ad-hoc signature
echo "Signing KEXT..."
codesign --force --sign - --deep "$KEXT_DST"

# Load
echo "Loading HidLensDriver.kext..."
kextload "$KEXT_DST"

if kextstat 2>/dev/null | grep -q "com.hidlens.driver"; then
    echo ""
    echo "SUCCESS! HidLensDriver KEXT loaded."
    echo "Run 'hidlens list' to see matched devices."
else
    echo ""
    echo "KEXT submitted for approval."
    echo "Check: System Settings → Privacy & Security → scroll down"
    echo "You should see a prompt to allow 'com.hidlens.driver'."
    echo "After approving, run this script again."
fi
