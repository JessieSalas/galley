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
ASC_KEY_ID="${ASC_KEY_ID:-43S9AKM5N9}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect API issuer UUID)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/Downloads/AuthKey_${ASC_KEY_ID}.p8}"
ASC_WHATS_NEW="${ASC_WHATS_NEW:-}"
# App Review Information -> Notes. Set this when resubmitting after a
# rejection and point the reviewer at the exact thing they said was missing.
ASC_REVIEW_NOTES="${ASC_REVIEW_NOTES:-}"

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

# appstoreconnect.py needs pyjwt/cryptography/requests, which the system
# python3 does not have. Discovering that at the final step, after a build
# and two notarizations, is the worst possible time — so build the venv now
# and prove the imports work before anything slow starts.
#
# Plain `python3` is whatever shadows first on PATH, which on a dev machine
# is often Anaconda's — and Anaconda's Python 3.9 build fails to import a
# freshly pip-installed `cryptography` with a linker error
# ("symbol not found ... _DTLS_get_data_mtu"): the wheel's Rust extension
# wants a newer OpenSSL than whatever Anaconda's own Python links against.
# Prefer a real Homebrew CPython (tested against current wheels) and only
# fall back to Apple's bundled /usr/bin/python3 if Homebrew isn't present.
ASC_PYTHON_BIN=""
for candidate in /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3 /usr/bin/python3; do
    [[ -x "$candidate" ]] && { ASC_PYTHON_BIN="$candidate"; break; }
done
[[ -n "$ASC_PYTHON_BIN" ]] || { echo "error: no usable python3 found for the App Store Connect venv" >&2; exit 1; }

ASC_VENV="$ROOT/build/.ascvenv"
if [[ ! -x "$ASC_VENV/bin/python" ]]; then
    echo "==> Creating Python venv for App Store Connect deps ($ASC_PYTHON_BIN)"
    "$ASC_PYTHON_BIN" -m venv "$ASC_VENV"
fi
"$ASC_VENV/bin/pip" install -q pyjwt cryptography requests
"$ASC_VENV/bin/python" -c "import jwt, requests" || {
    echo "error: App Store Connect Python deps unavailable" >&2; exit 1; }
ASC_PY="$ASC_VENV/bin/python"

echo "==> Tests: web renderer"
# The dialect/callout logic is JavaScript, so the Swift suite can't cover it.
# Skipped rather than failed when node is absent: the committed bundles mean
# a release doesn't otherwise need node at all.
if command -v node >/dev/null 2>&1; then
    node "$ROOT/web/test.mjs"
else
    echo "  skipped (node not installed)"
fi

echo "==> Tests"
# Runs before the version bump so a red suite stops the release without
# leaving a stray bump commit behind. 1.1.5 shipped a Guideline 4 rejection
# that WindowMenuReopenTests catches, and the suite had never run at all
# because the test target could not code sign — so this gate is the point.
xcodebuild -project Galley.xcodeproj -scheme Galley -configuration Debug \
    -derivedDataPath "$ROOT/build/test-$VERSION" test
echo "  tests passed"

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

SHIPPED_GITHUB=false
SHIPPED_THESIS=false
SHIPPED_APPSTORE=false

if ! $SKIP_GITHUB; then
    if confirm "Push v$VERSION to origin/main and publish a public GitHub release with the DMG+zip?"; then
        git push origin main --tags
        gh release create "v$VERSION" \
            "$BUILD_DIR/Galley-$VERSION.dmg" "$BUILD_DIR/Galley-$VERSION.zip" \
            --title "Galley $VERSION" --generate-notes
        SHIPPED_GITHUB=true
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
        SHIPPED_THESIS=true
    else
        echo "  skipped"
    fi
fi

if ! $SKIP_APPSTORE; then
    if confirm "Upload build $NEW_BUILD (v$VERSION) to App Store Connect and submit for review?"; then
        "$ASC_PY" "$ROOT/scripts/appstoreconnect.py" submit \
            --version "$VERSION" \
            --pkg "$BUILD_DIR/export-appstore/Galley.pkg" \
            --key-id "$ASC_KEY_ID" --issuer-id "$ASC_ISSUER_ID" --key-path "$ASC_KEY_PATH" \
            ${ASC_WHATS_NEW:+--whats-new "$ASC_WHATS_NEW"} \
            ${ASC_REVIEW_NOTES:+--review-notes "$ASC_REVIEW_NOTES"}
        SHIPPED_APPSTORE=true
    else
        echo "  skipped — the exported .pkg is at $BUILD_DIR/export-appstore/Galley.pkg"
    fi
fi

# A release that reaches only some channels is how 1.1.5 ended up live on
# the App Store while GitHub had no tag and thesis.do still served 1.1.4.
# The three ship together or the run is reported as a failure.
echo
echo "==> Channel summary for v$VERSION"
status_line() { $2 && echo "    shipped     $1" || echo "    NOT SHIPPED $1"; }
status_line "GitHub release + origin/main" $SHIPPED_GITHUB
status_line "thesis.do (THESIS repo)" $SHIPPED_THESIS
status_line "App Store Connect" $SHIPPED_APPSTORE

if ! $SHIPPED_GITHUB || ! $SHIPPED_THESIS || ! $SHIPPED_APPSTORE; then
    echo
    echo "error: v$VERSION did not reach every channel, so they are now out of sync." >&2
    echo "       Re-run the missing channel(s) before considering this release done." >&2
    exit 1
fi

echo "==> Done"
