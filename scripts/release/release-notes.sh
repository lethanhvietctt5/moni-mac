#!/bin/bash
# Writes the release notes as Markdown to standard output: the install steps (with the Open Anyway
# screenshots once they're in docs/images), how updates work, and what changed since the previous tag.
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

screenshot() { # Only screenshots that exist; the README says which ones the maintainer still has to add.
    [ -f "$ROOT/docs/images/$1" ] && printf "\n   %s" "![$2](https://raw.githubusercontent.com/$REPO/$TAG/docs/images/$1)" || true
}

cat <<EOF
## Install

1. Download **MoniMac-$VERSION.dmg** below and open it.
2. Drag **MoniMac** onto the **Applications** shortcut next to it, then eject the disk image.
3. Open MoniMac. macOS says it can't verify that MoniMac is free of malware. Click **Done**.$(screenshot install-blocked.png "macOS blocks MoniMac on first launch")
4. Open **System Settings › Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to "MoniMac was blocked". Confirm with **Open Anyway** and your password.$(screenshot install-open-anyway.png "Open Anyway in System Settings › Privacy & Security")

MoniMac is free and open source, and isn't notarized by Apple (that needs a paid developer account), so macOS asks you to approve it once. You only do this on the first install.

## Updates

MoniMac checks this page's update feed and offers new versions itself (**Settings › Data & About › Check for Updates…**). Updates are verified with the project's signing key. Sparkle clears the quarantine flag from the update it installs, so it shouldn't need the Open Anyway step, and every release is signed with the same certificate, so the permissions you've granted should carry over.

## What's changed

$(changes)
EOF
