#!/bin/bash
# Packs the signed app into a disk image for GitHub Releases and Sparkle. Prints the image's path.
#
# Usage: scripts/release/package.sh path/to/MoniMac.app out-dir
#
# The image holds MoniMac.app and an Applications shortcut, so installing is one drag. It's compressed
# (UDZO) and read-only. Sparkle installs updates straight from it.
source "$(dirname "$0")/common.sh"

APP="${1:?usage: $0 MoniMac.app out-dir}"
OUT="${2:?usage: $0 MoniMac.app out-dir}"
VERSION="$(plist_value "$APP" CFBundleShortVersionString)"
DMG="$OUT/MoniMac-$VERSION.dmg"

STAGING="$(mktemp -d)"
MOUNT="$(mktemp -d)"
cleanup() {
    hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
    rm -rf "$STAGING" "$MOUNT"
}
trap cleanup EXIT

# ditto keeps the framework symlinks and extended attributes that Sparkle.framework's signature covers.
ditto "$APP" "$STAGING/MoniMac.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT"
rm -f "$DMG"
hdiutil create -quiet -volname "MoniMac $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

# The image must mount to an app whose signature still holds, next to the Applications shortcut.
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
codesign --verify --deep --strict "$MOUNT/MoniMac.app" || die "the app in the disk image doesn't verify"
[ "$(readlink "$MOUNT/Applications")" = /Applications ] || die "the disk image has no Applications shortcut"
echo "$DMG"
