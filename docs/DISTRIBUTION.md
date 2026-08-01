# Distributing Galley

Two channels, one codebase: notarized direct download (DMG + thesis.do +
GitHub Releases) and the Mac App Store. The sandbox configuration is
identical for both.

## 0. One-time setup

- Apple Developer Program membership
- In `project.yml`, set your team: add `DEVELOPMENT_TEAM: <TEAMID>` under
  `settings.base`, then `xcodegen generate`
- Certificates: *Developer ID Application* (direct) and *Apple Distribution*
  (App Store), both via Xcode → Settings → Accounts
- An App Store Connect API key (Users and Access → Integrations → App Store
  Connect API, App Manager role or higher) — one key covers notarization,
  App Store build upload, and review submission. Note its Key ID, Issuer ID,
  and where the downloaded `AuthKey_<id>.p8` lives.
- A local checkout of the `THESIS` repo (thesis.do's site, auto-deploys on
  push to `main`) at `~/Projects/THESIS`, or set `THESIS_REPO` to point at
  yours.

## 1. Standardized release: `scripts/release.sh`

Everything below — archive, dual export, notarize, staple, package, and
push to GitHub Releases + thesis.do + App Store Connect — is one script:

```bash
ASC_ISSUER_ID=<issuer-uuid> ./scripts/release.sh 1.1.5
```

It bumps `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in `project.yml`,
builds and verifies everything locally first, then pauses for an explicit
`y/N` before each externally-visible step (pushing the tag/GitHub release,
pushing thesis.do to production, and submitting to App Store review) — pass
`--yes` to skip prompts once you've reviewed a run, or `--skip-github` /
`--skip-thesis` / `--skip-appstore` to leave a channel out entirely. See the
script's own comments for the full step list and environment variables
(`ASC_KEY_ID`, `ASC_KEY_PATH`, `THESIS_REPO`).

App Store Connect submission itself is driven by
[`scripts/appstoreconnect.py`](../scripts/appstoreconnect.py) (called
automatically by `release.sh`, or runnable standalone) via the current
(2026) `reviewSubmissions` API — upload, wait for processing, attach the
build to the version, submit. It expects the App Store version (with its
"What's New" text) to already exist in App Store Connect; creating that is
still a two-minute dashboard step since it clones the prior version's
metadata. Run `python3 scripts/appstoreconnect.py status --key-id ... --issuer-id ... --key-path ...`
any time for a read-only check of the app's current versions/builds.

Once a release ships, claim the Homebrew cask if you haven't yet — the name
`galley` was verified unclaimed (2026-07):

```bash
brew bump-cask-pr --version 1.0.0 galley   # after submitting the new cask
```

## 2. Mac App Store

- **Listing name**: `Galley — Markdown Reader` (bare "Galley" is held by an
  out-of-category food app; the suffixed form is standard practice)
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
- "Set as Default" (Settings → Reading, and offered once during first-run
  onboarding) calls the sanctioned `NSWorkspace.setDefaultApplication` API —
  works fine sandboxed despite older reports of `permErr`, is always
  user-tap-initiated, never automatic, and only ever asked once
- `ITSAppUsesNonExemptEncryption` is `NO`
- Print uses `printOperation(with:)` with the explicit `view.frame` assignment
  (macOS 26 crash workaround)
- Quick Look extension never fights the sandbox for sibling images
- Test double-click open of a file in `~/Downloads` (quarantined) — renders
  with zero dialogs
- **Guideline 4 (rejected on 1.1.0):** closing the last document window left
  no menu item to reopen one. Fixed by adding the existing "Welcome to
  Galley" action to the Window menu (`CommandGroup(after: .windowArrangement)`
  in `GalleyCommands.swift`), not just Help.

## 3. Versioning

`scripts/release.sh <version>` handles this. To do it by hand: bump
`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`,
`xcodegen generate`, commit, tag `v<version>`.
