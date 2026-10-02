#!/bin/bash
# Publishes a MoniMac release from this Mac: no signing certificate, no CI secrets.
#
#   1. builds Release with updates on and the version from the tag
#   2. checks the app carries the real Sparkle public key
#   3. signs it ad-hoc
#   4. packs it into MoniMac-x.y.z.dmg
#   5. signs the DMG with the Sparkle private key and writes appcast.xml (the feed "Check for Updates…" reads)
#   6. tags the release and publishes it on GitHub with the DMG, the appcast, and install notes
#
# Usage:
#   scripts/release/release-local.sh v1.2.3             builds and publishes
#   scripts/release/release-local.sh v1.2.3 --dry-run   builds everything into dist/, publishes nothing
#
# Needs the Sparkle private key as a file (default ~/.monimac/sparkle-ed-key, or $SPARKLE_KEY_FILE): the
# one `generate_keys -x` exports. Keep a backup of it: without it, installed copies can't be updated.
#
# Ad-hoc signing: each release has a different code signature, so macOS may ask again for permissions
# (Location, notifications, audio capture) after an update. Sparkle trusts the update through the EdDSA key.
source "$(dirname "$0")/common.sh"

TAG="${1:?usage: $0 v1.2.3 [--dry-run]}"
DRY_RUN=false
[ "${2:-}" = --dry-run ] && DRY_RUN=true
VERSION="$(version_from_tag "$TAG")"
KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/.monimac/sparkle-ed-key}"
RELEASE="$ROOT/scripts/release"

[ -s "$KEY_FILE" ] || die "no Sparkle private key at $KEY_FILE (see README › Releasing)"
cd "$ROOT"
if ! $DRY_RUN; then
    command -v gh >/dev/null || die "gh is missing (brew install gh)"
    [ "$(git branch --show-current)" = main ] || die "release from main"
    [ -z "$(git status --porcelain --untracked-files=no)" ] || die "commit or stash your changes first"
    git fetch --quiet origin main --tags
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main isn't up to date with origin/main"
    ! git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null || die "$TAG already exists"
fi

APP="$("$RELEASE/build.sh" "$TAG")"
"$RELEASE/check-update-key.sh" "$APP"
"$RELEASE/sign.sh" "$APP" -

rm -rf "$DIST"
DMG="$("$RELEASE/package.sh" "$APP" "$DIST")"
SIGNATURE="$(SPARKLE_ED_PRIVATE_KEY="$(cat "$KEY_FILE")" "$RELEASE/appcast.sh" "$APP" "$DMG" "$DIST/appcast.xml")"
# The DMG must verify against the public key the app ships, or no installed copy would accept it.
swift "$RELEASE/verify-signature.swift" "$(plist_value "$APP" SUPublicEDKey)" "$DMG" "$SIGNATURE"
"$RELEASE/release-notes.sh" "$TAG" >"$DIST/release-notes.md"

if $DRY_RUN; then
    echo "Dry run: ready in $DIST, nothing published."
    ls -l "$DIST"
    exit 0
fi

git tag "$TAG"
git push --quiet origin "$TAG"
# --latest: the feed URL (releases/latest/download/appcast.xml) follows the release GitHub marks as latest.
gh release create "$TAG" "$DMG" "$DIST/appcast.xml" --repo "$REPO" --verify-tag --latest \
    --title "MoniMac $VERSION" --notes-file "$DIST/release-notes.md"
echo "Published: https://github.com/$REPO/releases/tag/$TAG"
