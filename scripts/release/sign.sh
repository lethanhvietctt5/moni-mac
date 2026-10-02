#!/bin/bash
# Signs the built app, and Sparkle's helpers inside it, with one identity, innermost code first.
#
# Usage: scripts/release/sign.sh path/to/MoniMac.app [identity]
#   identity: a name or SHA-1 hash in the keychain search list, or "-" (ad-hoc, for a local dry run).
#   Defaults to $SIGNING_IDENTITY, which import-certificate.sh sets in CI.
#
# Why re-sign Sparkle: its Swift package ships the helpers (Autoupdate, Updater.app, the XPC services) ad-hoc
# signed, and Xcode's Embed & Sign only re-signs the framework's outer layer.
#
# Hardened runtime: the app is signed WITHOUT it. It's needed only for notarization, which needs a paid account.
# With a self-signed certificate (no Team ID), its library validation would refuse to load Sparkle.framework
# unless disabled by entitlement, and audio capture and location would need extra entitlements. Sparkle's
# helpers keep the runtime flag Sparkle built them with: they link only system libraries, so it costs nothing.
#
# Timestamps are off (as in Config/Signing.xcconfig): Apple's timestamp service is for Apple-issued certificates.
source "$(dirname "$0")/common.sh"

APP="${1:?usage: $0 MoniMac.app [identity]}"
IDENTITY="${2:-${SIGNING_IDENTITY:--}}"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"

sign() { codesign --force --sign "$IDENTITY" --timestamp=none "$@"; }

# Keep each helper's identifier, entitlements, and runtime flag; replace only the signer.
for helper in "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    [ -e "$helper" ] || die "missing $helper; has Sparkle's layout changed?"
    sign --preserve-metadata=identifier,entitlements,flags "$helper"
done
# The app has no entitlements: it isn't sandboxed, and Release builds carry no get-task-allow.
sign "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Designated requirement (permissions are tied to it, so it must stay the same across releases):"
codesign --display --requirements - "$APP" 2>&1 | grep designated
