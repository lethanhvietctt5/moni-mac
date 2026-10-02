#!/bin/bash
# CI only. Publishes the GitHub release for a tag with what make-release.sh put in dist/: the zip, appcast.xml
# (which apps read at releases/latest/download/appcast.xml), and the release notes with the install steps.
#
# Usage: scripts/release/publish.sh v1.2.3   (needs GH_TOKEN with contents: write)
source "$(dirname "$0")/common.sh"
refuse_outside_ci

TAG="${1:?usage: $0 v1.2.3}"
VERSION="$(version_from_tag "$TAG")"
ZIP="$DIST/MoniMac-$VERSION.zip"
for file in "$ZIP" "$DIST/appcast.xml" "$DIST/release-notes.md"; do
    [ -f "$file" ] || die "missing $file; run make-release.sh first"
done

# --latest: the feed URL follows the release GitHub marks as latest.
gh release create "$TAG" "$ZIP" "$DIST/appcast.xml" \
    --repo "$REPO" --verify-tag --latest \
    --title "MoniMac $VERSION" --notes-file "$DIST/release-notes.md"
