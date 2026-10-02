#!/bin/bash
# Fails unless the app can take updates: updates on, a feed, and a real EdDSA public key (not the placeholder).
# A release without the real key could never be updated, so the workflow stops here.
#
# Usage: scripts/release/check-update-key.sh path/to/MoniMac.app
source "$(dirname "$0")/common.sh"

APP="${1:?usage: $0 MoniMac.app}"
KEY="$(plist_value "$APP" SUPublicEDKey 2>/dev/null || true)"

[ "$(plist_value "$APP" MoniMacUpdatesEnabled 2>/dev/null || true)" = YES ] || die "MoniMacUpdatesEnabled isn't YES; build with build.sh"
[ -n "$(plist_value "$APP" SUFeedURL 2>/dev/null || true)" ] || die "SUFeedURL is missing"
[ "$KEY" != "$PLACEHOLDER_KEY" ] || die "SUPublicEDKey is still the placeholder. Put the real public key in project.yml (README › Releasing)."
# An Ed25519 public key is 32 bytes, base64-encoded.
[ "$(printf '%s' "$KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" = 32 ] || die "SUPublicEDKey '$KEY' isn't a base64 Ed25519 public key"
echo "Update key OK: $KEY"
