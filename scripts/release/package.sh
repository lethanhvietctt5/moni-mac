#!/bin/bash
# Zips the signed app for GitHub Releases and Sparkle. Prints the zip's path.
#
# Usage: scripts/release/package.sh path/to/MoniMac.app out-dir
#
# ditto keeps the framework symlinks and extended attributes; a zip that follows symlinks breaks
# Sparkle.framework's signature.
source "$(dirname "$0")/common.sh"

APP="${1:?usage: $0 MoniMac.app out-dir}"
OUT="${2:?usage: $0 MoniMac.app out-dir}"
VERSION="$(plist_value "$APP" CFBundleShortVersionString)"
ZIP="$OUT/MoniMac-$VERSION.zip"

mkdir -p "$OUT"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# The archive must unpack to an app whose signature still holds.
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/MoniMac.app" || die "the zipped app's signature doesn't verify"
echo "$ZIP"
