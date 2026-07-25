#!/bin/bash
# Regenerates scripts/dmg/background.png from background.html after a
# brand/copy change. Uses the same offscreen WKWebView snapshot pipeline
# as the rest of the launch screenshots (scripts/snapshot.swift).
#
# background.html is a fixed 660x420-point design (matching the DMG
# window size make-dmg.sh sets) — and it MUST end up exactly 660x420
# pixels. Confirmed empirically: unlike icon views elsewhere in macOS,
# Finder's DMG background picture is placed at native pixel size mapped
# 1:1 to window points, not scaled to fit — a 2x/retina asset here
# renders as if it were 2x the window size and gets cropped to the
# window's top-left quadrant instead of being shown scaled down. So
# this intentionally ships a 1x asset, sized exactly to match.
#
# Getting there needs a detour: requesting the design's literal point
# size (660x420) from the snapshot tool clips content — its own
# viewport for "html" jobs comes out smaller than that. Requesting
# double (1320x840) gives a viewport that fits the design, then the
# tool captures at 2x THAT (2640x1680) regardless of what was asked
# for. Downsample straight to 660x420 for the final 1:1 asset.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"

JOB=$(mktemp -t dmg-bg-job).json
RAW=$(mktemp -t dmg-bg-raw).png
trap 'rm -f "$JOB" "$RAW"' EXIT
cat > "$JOB" << EOF
[{
  "type": "html",
  "htmlFile": "$DIR/background.html",
  "pixelWidth": 1320,
  "pixelHeight": 840,
  "output": "$RAW",
  "waitSeconds": 0.6
}]
EOF

swift "$REPO/scripts/snapshot.swift" "$JOB"
sips -Z 660 "$RAW" --out "$DIR/background.png" >/dev/null
echo "✓ $DIR/background.png"
