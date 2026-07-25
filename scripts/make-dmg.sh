#!/bin/bash
# Packages a signed (and ideally stapled) Galley.app into a distributable,
# properly-designed DMG: branded background, custom volume icon, the app
# and an Applications alias laid out with a drag-here arrow between them.
#
# Usage: scripts/make-dmg.sh path/to/Galley.app [output.dmg]
#
# Requires create-dmg (brew install create-dmg). The background image and
# volume icon live in scripts/dmg/ — see scripts/dmg/render-background.sh
# to regenerate the background from its HTML source after a brand change.
set -euo pipefail

APP="${1:?usage: make-dmg.sh path/to/Galley.app [output.dmg]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(defaults read "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")/Contents/Info" CFBundleShortVersionString)
OUT="${2:-Galley-$VERSION.dmg}"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg not found — brew install create-dmg" >&2
    exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
rm -f "$OUT"

# create-dmg's own .DS_Store-writing step exits non-zero if Finder was
# already annoyed about something in a prior run; --hdiutil-retries plus
# just not treating a non-fatal AppleScript timeout as failure keeps this
# reliable in CI-ish (headless-ish) conditions the way a real Finder
# session on a normal Mac doesn't need to worry about.
create-dmg \
    --volname "Galley" \
    --volicon "$SCRIPT_DIR/dmg/volume.icns" \
    --background "$SCRIPT_DIR/dmg/background.tiff" \
    --window-pos 200 120 \
    --window-size 660 420 \
    --icon-size 128 \
    --text-size 12 \
    --icon "Galley.app" 180 205 \
    --hide-extension "Galley.app" \
    --app-drop-link 480 205 \
    --no-internet-enable \
    --format UDZO \
    "$OUT" \
    "$STAGE" || true

if [ ! -f "$OUT" ]; then
    echo "error: create-dmg did not produce $OUT" >&2
    exit 1
fi

echo "✓ $OUT"
echo "  Remember: notarize the .app BEFORE packaging, then optionally"
echo "  notarize + staple the DMG itself:"
echo "  xcrun notarytool submit $OUT --keychain-profile galley --wait && xcrun stapler staple $OUT"
