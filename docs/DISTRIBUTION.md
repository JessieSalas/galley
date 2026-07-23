# Distributing Galley

Two channels, one codebase: notarized direct download (DMG) and the Mac App
Store. The sandbox configuration is identical for both.

## 0. One-time setup

- Apple Developer Program membership
- In `project.yml`, set your team: add `DEVELOPMENT_TEAM: <TEAMID>` under
  `settings.base`, then `xcodegen generate`
- Certificates: *Developer ID Application* (direct) and *Apple Distribution*
  (App Store), both via Xcode → Settings → Accounts

## 1. Direct distribution (DMG + notarization)

```bash
# Archive
xcodebuild -project Galley.xcodeproj -scheme Galley -configuration Release \
  -archivePath build/Galley.xcarchive archive

# Export with Developer ID signing
xcodebuild -exportArchive -archivePath build/Galley.xcarchive \
  -exportPath build/export -exportOptionsPlist docs/ExportOptions-developer-id.plist

# Notarize (store credentials once with `xcrun notarytool store-credentials`)
xcrun notarytool submit build/export/Galley.app --keychain-profile galley --wait
xcrun stapler staple build/export/Galley.app

# Package
./scripts/make-dmg.sh build/export/Galley.app
```

Publish the DMG on GitHub Releases. Then claim the Homebrew cask — the name
`galley` was verified unclaimed (2026-07):

```bash
brew bump-cask-pr --version 1.0.0 galley   # after submitting the new cask
```

## 2. Mac App Store

- **Listing name**: `Galley — Markdown Reader` (bare "Galley" is held by an
  out-of-category food app; the suffixed form is standard practice)
- Archive with the same scheme, choose *App Store Connect* in Organizer (or
  `-exportOptionsPlist` with `method: app-store-connect`)
- Metadata and review notes: [appstore/metadata.md](appstore/metadata.md)

### Review notes to include verbatim

> Galley is a read-only Markdown viewer. The `com.apple.security.network.client`
> entitlement exists because WKWebView's out-of-process networking requires it
> even for purely local content, and because documents may reference remote
> images (user-disableable in Settings → Privacy). All rendering libraries are
> bundled; the app makes no network requests of its own, has no analytics, and
> no accounts. The folder-access panel appears only when a document references
> local images outside its own file, and the grant is stored as a
> security-scoped bookmark so users are never re-asked.

### Known review pitfalls (pre-checked in this codebase)

- Rank is `Alternate` for `net.daringfireball.markdown` — Galley never seizes
  the user's default handler
- No "set as default" button — sandboxed `NSWorkspace.setDefaultApplication`
  fails with `permErr`; Settings shows Get Info → Change All guidance instead
- `ITSAppUsesNonExemptEncryption` is `NO`
- Print uses `printOperation(with:)` with the explicit `view.frame` assignment
  (macOS 26 crash workaround)
- Quick Look extension never fights the sandbox for sibling images
- Test double-click open of a file in `~/Downloads` (quarantined) — renders
  with zero dialogs

## 3. Versioning

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`,
`xcodegen generate`, commit, tag `v<version>`.
