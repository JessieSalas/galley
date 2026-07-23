#!/bin/bash
# Packages a signed (and ideally stapled) Galley.app into a distributable DMG.
# Usage: scripts/make-dmg.sh path/to/Galley.app [output.dmg]
set -euo pipefail

APP="${1:?usage: make-dmg.sh path/to/Galley.app [output.dmg]}"
VERSION=$(defaults read "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")/Contents/Info" CFBundleShortVersionString)
OUT="${2:-Galley-$VERSION.dmg}"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Galley" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "✓ $OUT"
echo "  Remember: notarize the .app BEFORE packaging, then optionally"
echo "  notarize + staple the DMG itself:"
echo "  xcrun notarytool submit $OUT --keychain-profile galley --wait && xcrun stapler staple $OUT"
