#!/bin/bash
# Writes the release notes as Markdown to standard output: the install steps (with the Terminal command that
# clears the quarantine flag), how updates work, and what changed since the previous tag.
#
# Usage: scripts/release/release-notes.sh v1.2.3 [--changes]
#   --changes prints only what changed, for the appcast (people updating don't need the install steps).
source "$(dirname "$0")/common.sh"

TAG="${1:?usage: $0 v1.2.3 [--changes]}"
VERSION="$(version_from_tag "$TAG")"
cd "$ROOT"

changes() {
    local previous
    previous="$(git tag --merged HEAD --list 'v*' --sort=-v:refname | grep -vxF "$TAG" | head -1 || true)"
    if [ -z "$previous" ]; then
        echo "- First release."
        return
    fi
    # One line per change on main since the previous release: a merged PR's title, or a direct commit's subject.
    git log --first-parent --format='%x1e%P%x1f%s%x1f%b' "$previous..HEAD" | awk -v RS='\036' -F '\037' '
        NF < 2 { next }
        {
            line = $2
            if (split($1, parents, " ") > 1) { split($3, body, "\n"); if (body[1] != "") line = body[1] }
            print "- " line
        }'
}

if [ "${2:-}" = --changes ]; then
    changes
    exit 0
fi

cat <<EOF
## Install

1. Download **MoniMac-$VERSION.dmg** below and open it.
2. Drag **MoniMac** onto the **Applications** shortcut next to it, then eject the disk image.
3. In Terminal, run this once:

   \`\`\`bash
   xattr -dr com.apple.quarantine /Applications/MoniMac.app
   \`\`\`

4. Open MoniMac from Applications, or with \`open -a MoniMac\`.

MoniMac is free and open source, and isn't notarized by Apple (that needs a paid developer account), so macOS blocks it while it carries the "downloaded from the internet" flag. Step 3 removes that flag. You only do it on the first install.

## Updates

MoniMac checks this page's update feed and offers new versions itself (**Settings › Data & About › Check for Updates…**). Updates are verified with the project's signing key, and Sparkle clears the quarantine flag from the update it installs, so updates don't need the Terminal step. macOS may ask again for permissions you granted (Location, notifications, audio) after an update.

## What's changed

$(changes)
EOF
