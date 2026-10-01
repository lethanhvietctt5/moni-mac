#!/bin/bash
# Screenshots only MoniMac's main window (by window ID), even when other windows cover it.
# Never capture the full screen: it records whatever else the user has open.
#
# Usage: scripts/screenshot-window.sh out.png
set -euo pipefail
OUT="${1:?usage: $0 out.png}"
ID=$(swift - <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "MoniMac" {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    if (bounds["Width"] ?? 0) > 600, (bounds["Height"] ?? 0) > 400 {
        print(window[kCGWindowNumber as String] ?? "")
        break
    }
}
SWIFT
)
[ -n "$ID" ] || { echo "No MoniMac window found. Launch with --show-window." >&2; exit 1; }
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
