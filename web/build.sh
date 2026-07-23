#!/bin/bash
# Rebuilds Galley's web assets from source and refreshes the vendored copies
# under Galley/Resources/web and QuickLook/Resources.
# The build outputs ARE committed, so cloning + building the Xcode project
# never requires node. Run this only when changing web/src or bumping deps.
set -euo pipefail
cd "$(dirname "$0")"

npm install --no-audit --no-fund

APP_WEB="../Galley/Resources/web"
QL_RES="../QuickLook/Resources"

npx esbuild src/render.js --bundle --minify --format=iife \
  --outfile="$APP_WEB/reader.bundle.js"
npx esbuild src/ql.js --bundle --minify --format=iife \
  --outfile="$QL_RES/ql.bundle.js"

# fonts (latin variable subsets only)
mkdir -p "$APP_WEB/fonts"
cp node_modules/@fontsource-variable/bricolage-grotesque/files/bricolage-grotesque-latin-wght-normal.woff2 "$APP_WEB/fonts/"
cp node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2 "$APP_WEB/fonts/"
cp node_modules/@fontsource-variable/inter/files/inter-latin-wght-italic.woff2 "$APP_WEB/fonts/"
cp node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2 "$APP_WEB/fonts/"
cp node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-italic.woff2 "$APP_WEB/fonts/"

# heavyweight vendors, loaded lazily by the renderer
mkdir -p "$APP_WEB/vendor/katex/fonts"
cp node_modules/mermaid/dist/mermaid.min.js "$APP_WEB/vendor/"
cp node_modules/katex/dist/katex.min.js node_modules/katex/dist/katex.min.css "$APP_WEB/vendor/katex/"
cp node_modules/katex/dist/contrib/auto-render.min.js "$APP_WEB/vendor/katex/"
cp node_modules/katex/dist/fonts/*.woff2 "$APP_WEB/vendor/katex/fonts/"

echo "✓ web assets rebuilt"
