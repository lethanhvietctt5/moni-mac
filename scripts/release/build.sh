#!/bin/bash
# Builds MoniMac for release, with updates on and the version taken from the tag. Prints the app's path.
#
# Usage: scripts/release/build.sh v1.2.3
#
# The build is ad-hoc signed here; sign.sh signs it with the stable identity afterwards, so this works
# without any identity (e.g. for a local dry run).
source "$(dirname "$0")/common.sh"

VERSION="$(version_from_tag "${1:?usage: $0 v1.2.3}")"
command -v xcodegen >/dev/null || die "xcodegen is missing (brew install xcodegen)"

cd "$ROOT"
xcodegen generate --quiet
# CFBundleVersion is the marketing version too: Sparkle compares it, and tags only go up.
xcodebuild -project MoniMac.xcodeproj -scheme MoniMac -configuration Release \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
    MONIMAC_UPDATES=YES CODE_SIGN_IDENTITY=- \
    build >&2

APP="$DERIVED/Build/Products/Release/MoniMac.app"
[ "$(plist_value "$APP" CFBundleShortVersionString)" = "$VERSION" ] || die "built app isn't version $VERSION"
echo "$APP"
