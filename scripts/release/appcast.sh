#!/bin/bash
# Signs the disk image with the project's EdDSA key and writes a one-item appcast.xml for it.
#
# Usage: scripts/release/appcast.sh path/to/MoniMac.app path/to/MoniMac-1.2.3.dmg out/appcast.xml
#   The private key comes from $SPARKLE_ED_PRIVATE_KEY (the file `generate_keys -x` writes: a base64 seed)
#   and reaches sign_update on standard input, never the keychain or the command line.
#
# The feed lives at releases/latest/download/appcast.xml, so each release carries its own appcast and the
# newest release's is the one apps read. One item is all Sparkle needs: it offers the newest version, and
# "Version History" links to the GitHub release.
source "$(dirname "$0")/common.sh"

APP="${1:?usage: $0 MoniMac.app MoniMac-x.y.z.dmg appcast.xml}"
ARCHIVE="${2:?usage: $0 MoniMac.app MoniMac-x.y.z.dmg appcast.xml}"
OUT="${3:?usage: $0 MoniMac.app MoniMac-x.y.z.dmg appcast.xml}"
[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] || die "SPARKLE_ED_PRIVATE_KEY is empty"

VERSION="$(plist_value "$APP" CFBundleShortVersionString)"
BUILD="$(plist_value "$APP" CFBundleVersion)"
MINIMUM="$(plist_value "$APP" LSMinimumSystemVersion)"
TAG="v$VERSION"

# Prints e.g.: sparkle:edSignature="…" length="12345"
ATTRIBUTES="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$(sparkle_bin sign_update)" --ed-key-file - "$ARCHIVE")"
[[ "$ATTRIBUTES" =~ sparkle:edSignature=\"([^\"]+)\" ]] || die "unexpected sign_update output: $ATTRIBUTES"
SIGNATURE="${BASH_REMATCH[1]}"
[[ "$ATTRIBUTES" =~ length=\"([0-9]+)\" ]] || die "unexpected sign_update output: $ATTRIBUTES"
LENGTH="${BASH_REMATCH[1]}"
[ "$LENGTH" = "$(stat -f %z "$ARCHIVE")" ] || die "sign_update's length doesn't match the disk image"

NOTES="$("$ROOT/scripts/release/release-notes.sh" "$TAG" --changes)"
NOTES="${NOTES//]]>/]] >}"   # keep the CDATA section closed only where we close it

mkdir -p "$(dirname "$OUT")"
cat >"$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MoniMac</title>
    <link>https://github.com/$REPO/releases</link>
    <description>MoniMac updates</description>
    <language>en</language>
    <item>
      <title>MoniMac $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[$NOTES]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$(basename "$ARCHIVE")" length="$LENGTH" type="application/x-apple-diskimage" sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$OUT" || die "appcast.xml isn't well-formed"
echo "$SIGNATURE"
