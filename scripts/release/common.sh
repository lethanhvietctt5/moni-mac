# Shared by the release scripts. Source it; don't run it.
#
# The release scripts run in this order (make-release.sh runs 1–6, the workflow runs all of them):
#   import-certificate.sh   CI only: the self-signed identity into a temporary keychain
#   1 build.sh              Release build, updates on, version from the tag
#   2 check-update-key.sh   refuses a build whose SUPublicEDKey is still the placeholder
#   3 sign.sh               re-signs Sparkle's helpers and the app with the stable identity
#   4 package.sh            the disk image (.dmg), with an Applications shortcut
#   5 appcast.sh            signs the disk image with the EdDSA key and writes appcast.xml
#   6 release-notes.sh      install steps and changes, for the GitHub release
#   publish.sh              CI only: the GitHub release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${GITHUB_REPOSITORY:-lethanhvietctt5/moni-mac}"
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
PLACEHOLDER_KEY="PLACEHOLDER_SPARKLE_PUBLIC_ED_KEY"

die() { echo "error: $*" >&2; exit 1; }

# "v1.2.3" → "1.2.3". Only plain x.y.z tags make releases, so Sparkle's version order matches the tags.
version_from_tag() {
    local tag="$1"
    [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "release tags look like v1.2.3, not '$tag'"
    echo "${BASH_REMATCH[1]}"
}

# Sparkle's command-line tools ship inside the Swift package, so they match the framework in the app.
sparkle_bin() {
    local dir="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
    [ -x "$dir/$1" ] || die "$dir/$1 is missing; run build.sh first so the Sparkle package is resolved"
    echo "$dir/$1"
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"; }

refuse_outside_ci() {
    [ "${GITHUB_ACTIONS:-}" = true ] || die "$(basename "$0") changes keychains or publishes; it runs only in GitHub Actions"
}
