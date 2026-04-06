#!/bin/bash
# HidLens KEXT uninstaller
# Usage: sudo ./uninstall-kext.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (sudo)."
    exit 1
fi

if kextstat | grep -q "com.hidlens.driver"; then
    echo "Unloading HidLensDriver.kext..."
    kextunload -b com.hidlens.driver
    echo "Success! HidLensDriver KEXT unloaded."
    echo "Devices restored to default polling rates."
else
    echo "HidLensDriver KEXT is not currently loaded."
fi
