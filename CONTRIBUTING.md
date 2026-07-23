# Contributing to Galley

Thanks for wanting to help. Galley has a narrow soul: **a read-only Markdown
reader that is beautiful, fast, and never touches the file.** Contributions
that sharpen that are welcome; contributions that turn it into an editor,
a notes app, or a platform will be declined kindly.

## Ground rules

- **No write paths.** Galley must never modify a document. This is checked in
  review before anything else.
- **No network, except document-referenced images.** No telemetry, no update
  pings, no CDNs. All rendering assets are bundled.
- **Default beauty over configurability.** A new setting needs a strong reason;
  a better default needs none.
- **Native first.** Chrome is SwiftUI/AppKit; the page is the only web surface.

## Getting set up

```bash
brew install xcodegen
git clone https://github.com/JessieSalas/galley && cd galley
xcodegen generate
open Galley.xcodeproj
```

The committed `Galley/Resources/web` bundles are the build outputs of `web/src`.
If you change anything under `web/src`, run `cd web && ./build.sh` and commit
the refreshed bundles alongside your source change.

## Testing checklist for renderer changes

Open `Galley/Resources/Samples/Tour.md` and verify, in both Paper and Ink:

- headings, lists, task lists, callouts, tables, footnotes
- code fences (language label, copy button, palette)
- mermaid diagrams re-theme when switching appearance
- KaTeX inline + display
- front matter card
- live reload: `echo '## New' >> file.md` keeps scroll position

## Commit style

Small, focused commits with imperative subjects. Reference issues where they
exist. Screenshots for anything visual — both themes.
