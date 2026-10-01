#!/bin/bash
# Screenshots one of MoniMac's own windows by window ID, even when other windows cover it.
# Never capture the full screen or a screen region: they record whatever else the user has open.
#
# Usage:
#   scripts/screenshot-window.sh window out.png     # main window (launch with --show-window)
#   scripts/screenshot-window.sh popover out.png    # popover (launch with --show-popover)
#   scripts/screenshot-window.sh items              # list MoniMac's status-layer windows, if macOS exposes them
set -euo pipefail
KIND="${1:?usage: $0 window|popover|items [out.png]}"
LIST=$(swift - <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "MoniMac" {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let (width, height) = (bounds["Width"] ?? 0, bounds["Height"] ?? 0)
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let onScreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
    // The main window is large; the popover is a tall panel; anything small at the status layer is an item.
    let kind = width > 600 && height > 400 ? "window" : (width > 300 && height > 200 ? "popover" : (layer == 25 ? "item" : "other"))
    print(kind, window[kCGWindowNumber as String] ?? "", Int(width), Int(height), onScreen ? "on" : "off")
}
SWIFT
)
if [ "$KIND" = items ]; then echo "$LIST" | awk '$1 == "item"'; exit 0; fi
OUT="${2:?usage: $0 $KIND out.png}"
ID=$(echo "$LIST" | awk -v k="$KIND" '$1 == k && $5 == "on" { print $2; exit }')
[ -n "$ID" ] || { echo "No on-screen MoniMac $KIND found. Launch with --show-$KIND." >&2; exit 1; }
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
