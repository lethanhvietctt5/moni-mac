#!/bin/bash
# Builds everything a release publishes into dist/: the signed zip, appcast.xml, and release-notes.md.
# It doesn't publish; the workflow runs publish.sh afterwards.
#
# Usage:
#   scripts/release/make-release.sh v1.2.3              in CI: needs SIGNING_IDENTITY and SPARKLE_ED_PRIVATE_KEY
#   scripts/release/make-release.sh v1.2.3 --dry-run    locally: ad-hoc signing, and the placeholder key is allowed
#
# A dry run still needs SPARKLE_ED_PRIVATE_KEY (use a throwaway key file, never the real one) and checks the
# signature only if DRY_RUN_PUBLIC_KEY holds the throwaway's public half. Never put a throwaway key in the app.
source "$(dirname "$0")/common.sh"

TAG="${1:?usage: $0 v1.2.3 [--dry-run]}"
DRY_RUN=false
if [ "${2:-}" = --dry-run ]; then
    [ "${GITHUB_ACTIONS:-}" != true ] || die "--dry-run isn't allowed in CI"
    DRY_RUN=true
fi
version_from_tag "$TAG" >/dev/null
RELEASE="$ROOT/scripts/release"

APP="$("$RELEASE/build.sh" "$TAG")"

if $DRY_RUN; then
    "$RELEASE/check-update-key.sh" "$APP" || echo "warning: dry run, continuing despite the update key check" >&2
    PUBLIC_KEY="${DRY_RUN_PUBLIC_KEY:-}"
    "$RELEASE/sign.sh" "$APP" -
else
    "$RELEASE/check-update-key.sh" "$APP"
    PUBLIC_KEY="$(plist_value "$APP" SUPublicEDKey)"
    [ -n "${SIGNING_IDENTITY:-}" ] || die "SIGNING_IDENTITY is empty; import-certificate.sh sets it"
    "$RELEASE/sign.sh" "$APP" "$SIGNING_IDENTITY"
fi

rm -rf "$DIST"
ZIP="$("$RELEASE/package.sh" "$APP" "$DIST")"
SIGNATURE="$("$RELEASE/appcast.sh" "$APP" "$ZIP" "$DIST/appcast.xml")"
if [ -n "$PUBLIC_KEY" ]; then
    swift "$RELEASE/verify-signature.swift" "$PUBLIC_KEY" "$ZIP" "$SIGNATURE"
else
    echo "warning: dry run without DRY_RUN_PUBLIC_KEY; the signature wasn't checked" >&2
fi
"$RELEASE/release-notes.sh" "$TAG" >"$DIST/release-notes.md"

echo "Ready in $DIST:"
ls -l "$DIST"
