#!/bin/bash
# Standardized release pipeline for Galley: one archive, exported twice
# (Developer ID for direct download + App Store Connect), notarized,
# stapled, packaged, and pushed to all three channels "push to prod" means
# for this project: GitHub Releases, thesis.do (the THESIS repo, which
# auto-deploys on push to main), and App Store Connect (build upload,
# attach, submit for review).
#
# Every externally-visible step (git push, gh release, thesis.do push, App
# Store submission) pauses for an explicit y/N confirmation. Pass --yes to
# skip all prompts once you've reviewed a dry run.
#
# Usage: scripts/release.sh <version> [--yes] [--skip-github] [--skip-thesis] [--skip-appstore]
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [--yes] [--skip-github] [--skip-thesis] [--skip-appstore]}"
shift || true

AUTO_YES=false
SKIP_GITHUB=false
SKIP_THESIS=false
SKIP_APPSTORE=false
for arg in "$@"; do
    case "$arg" in
        --yes) AUTO_YES=true ;;
        --skip-github) SKIP_GITHUB=true ;;
        --skip-thesis) SKIP_THESIS=true ;;
        --skip-appstore) SKIP_APPSTORE=true ;;
        *) echo "error: unknown flag $arg" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

THESIS_REPO="${THESIS_REPO:-$HOME/Projects/THESIS}"
ASC_KEY_ID="${ASC_KEY_ID:-KL448V4YTJ}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect API issuer UUID)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/Downloads/AuthKey_${ASC_KEY_ID}.p8}"
ASC_WHATS_NEW="${ASC_WHATS_NEW:-}"

BUILD_DIR="$ROOT/build/release-$VERSION"

confirm() {
    $AUTO_YES && return 0
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

echo "==> Preflight"
[[ -f "$ASC_KEY_PATH" ]] || { echo "error: App Store Connect API key not found at $ASC_KEY_PATH" >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree not clean — commit or stash first" >&2
    exit 1
fi
if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
    echo "error: releases ship from main" >&2
    exit 1
fi

CURRENT_BUILD=$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml)
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
xcodegen generate

if ! git diff --quiet -- web/src 2>/dev/null; then
    echo "error: web/src changed but committed bundles weren't rebuilt — run web/build.sh first" >&2
    exit 1
fi

git add project.yml Galley.xcodeproj
git commit -m "Bump version to $VERSION"
git tag "v$VERSION"
echo "  committed + tagged v$VERSION locally (not pushed yet)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archive"
xcodebuild -project Galley.xcodeproj -scheme Galley -configuration Release \
    -archivePath "$BUILD_DIR/Galley.xcarchive" -allowProvisioningUpdates archive

echo "==> Export: Developer ID (direct download)"
xcodebuild -exportArchive -archivePath "$BUILD_DIR/Galley.xcarchive" \
    -exportPath "$BUILD_DIR/export-developer-id" \
    -exportOptionsPlist docs/ExportOptions-developer-id.plist \
    -allowProvisioningUpdates

echo "==> Export: App Store Connect"
xcodebuild -exportArchive -archivePath "$BUILD_DIR/Galley.xcarchive" \
    -exportPath "$BUILD_DIR/export-appstore" \
    -exportOptionsPlist docs/ExportOptions-app-store-connect.plist \
    -allowProvisioningUpdates

APP="$BUILD_DIR/export-developer-id/Galley.app"

echo "==> Notarize + staple the app (Developer ID build)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/Galley-app-submission.zip"
xcrun notarytool submit "$BUILD_DIR/Galley-app-submission.zip" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$APP"

echo "==> Package DMG + zip"
"$ROOT/scripts/make-dmg.sh" "$APP" "$BUILD_DIR/Galley-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/Galley-$VERSION.zip"

echo "==> Notarize + staple the DMG"
xcrun notarytool submit "$BUILD_DIR/Galley-$VERSION.dmg" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$BUILD_DIR/Galley-$VERSION.dmg"

echo "==> Verify"
spctl -a -vvv "$APP"
stapler validate "$APP"
stapler validate "$BUILD_DIR/Galley-$VERSION.dmg"

echo
echo "Built and verified:"
echo "  $BUILD_DIR/Galley-$VERSION.dmg"
echo "  $BUILD_DIR/Galley-$VERSION.zip"
echo "  $BUILD_DIR/export-appstore/Galley.pkg"

if ! $SKIP_GITHUB; then
    if confirm "Push v$VERSION to origin/main and publish a public GitHub release with the DMG+zip?"; then
        git push origin main --tags
        gh release create "v$VERSION" \
            "$BUILD_DIR/Galley-$VERSION.dmg" "$BUILD_DIR/Galley-$VERSION.zip" \
            --title "Galley $VERSION" --generate-notes
    else
        echo "  skipped (commit/tag remain local — push manually with: git push origin main --tags)"
    fi
fi

if ! $SKIP_THESIS; then
    if confirm "Push v$VERSION to thesis.do (production deploy via the THESIS repo)?"; then
        [[ -d "$THESIS_REPO/.git" ]] || { echo "error: $THESIS_REPO is not a git checkout" >&2; exit 1; }
        OLD_DMG=$(ls "$THESIS_REPO"/public/galley/Galley-*.dmg 2>/dev/null | head -1 || true)
        cp "$BUILD_DIR/Galley-$VERSION.dmg" "$THESIS_REPO/public/galley/Galley-$VERSION.dmg"
        git -C "$THESIS_REPO" add "public/galley/Galley-$VERSION.dmg"
        if [[ -n "$OLD_DMG" && "$(basename "$OLD_DMG")" != "Galley-$VERSION.dmg" ]]; then
            OLD_VERSION=$(basename "$OLD_DMG" .dmg | sed 's/^Galley-//')
            sed -i '' "s/Galley-$OLD_VERSION\\.dmg/Galley-$VERSION.dmg/" "$THESIS_REPO/app/galley/galley-page-client.tsx"
            git -C "$THESIS_REPO" rm -q "$OLD_DMG"
            git -C "$THESIS_REPO" add app/galley/galley-page-client.tsx
        fi
        git -C "$THESIS_REPO" commit -m "Ship Galley $VERSION"
        git -C "$THESIS_REPO" push origin main
    else
        echo "  skipped"
    fi
fi

if ! $SKIP_APPSTORE; then
    if confirm "Upload build $NEW_BUILD (v$VERSION) to App Store Connect and submit for review?"; then
        python3 "$ROOT/scripts/appstoreconnect.py" submit \
            --version "$VERSION" \
            --pkg "$BUILD_DIR/export-appstore/Galley.pkg" \
            --key-id "$ASC_KEY_ID" --issuer-id "$ASC_ISSUER_ID" --key-path "$ASC_KEY_PATH" \
            ${ASC_WHATS_NEW:+--whats-new "$ASC_WHATS_NEW"}
    else
        echo "  skipped — the exported .pkg is at $BUILD_DIR/export-appstore/Galley.pkg"
    fi
fi

echo "==> Done"
