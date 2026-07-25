#!/bin/bash
# Regenerates scripts/dmg/background.tiff from background.html after a
# brand/copy change. Uses the same offscreen WKWebView snapshot pipeline
# as the rest of the launch screenshots (scripts/snapshot.swift).
#
# background.html is a fixed 660x420-point design (matching the DMG
# window size make-dmg.sh sets). Confirmed empirically: Finder places a
# DMG background picture at native pixel size mapped 1:1 to window
# points — a plain 2x/retina PNG here doesn't render sharp-and-scaled,
# it renders cropped to the window's top-left quadrant, and a plain 1x
# PNG renders correctly-sized but soft on every actual Retina display
# (which is to say, every current Mac). The fix Finder does honor is a
# multi-resolution TIFF: one 1x representation, one 2x, combined with
# `tiffutil -cathidpicheck`, exactly like a status-bar icon or any other
# old-school HiDPI AppKit resource. Finder then picks whichever
# representation matches the actual screen at mount time.
#
# Getting a correctly-FIT render needs a detour first: requesting the
# design's literal point size (660x420) from the snapshot tool clips
# content — its own viewport for "html" jobs comes out smaller than
# that. Requesting double (1320x840) gives a viewport that fits the
# design, and the tool then captures at 2x THAT (2640x1680) regardless
# of what was asked for. That 2640x1680 master is downsampled to both
# the 1x (660x420) and 2x (1320x840) reps the TIFF needs.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"

JOB=$(mktemp -t dmg-bg-job).json
RAW=$(mktemp -t dmg-bg-raw).png
REP1X=$(mktemp -t dmg-bg-1x).png
REP2X=$(mktemp -t dmg-bg-2x).png
trap 'rm -f "$JOB" "$RAW" "$REP1X" "$REP2X"' EXIT
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
sips -Z 660 "$RAW" --out "$REP1X" >/dev/null
sips -Z 1320 "$RAW" --out "$REP2X" >/dev/null
tiffutil -cathidpicheck "$REP1X" "$REP2X" -out "$DIR/background.tiff" >/dev/null
rm -f "$DIR/background.png"
echo "✓ $DIR/background.tiff (1x 660x420 + 2x 1320x840)"
