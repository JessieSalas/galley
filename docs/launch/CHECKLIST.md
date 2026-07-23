# Launch checklist

Status as of 2026-07-23. Source plan: [LAUNCH.md](../LAUNCH.md) section 9.

## Phase 0, today

- [x] Screenshots captured and processed. `docs/launch/screenshots/` (App
      Store crops and web crops) and `site/assets/` are in the repo.
- [x] GitHub repo public, links consistent, README with images. Repo is
      live at https://github.com/JessieSalas/galley, every
      `thesis-labs/galley` reference in the app and docs now points to
      `JessieSalas/galley`, and the README has the hero and themes
      screenshots plus an Install section.
- [x] Landing page in repo. `site/index.html` ships in this repo.
- [x] thesis.do route and homepage card committed to the THESIS repo,
      locally. Confirmed by running `git log --oneline -1` in
      `~/Projects/THESIS`:

      ```
      dc30449 Add galley: /galley product page and homepage presence
      ```

      That commit is local only, `git status` in THESIS shows the branch
      one commit ahead of `origin/main`, not yet pushed. It touches
      `app/galley/page.tsx`, `app/galley/galley-page-client.tsx`,
      `app/page.tsx`, `app/globals.css`, and five images under
      `public/galley/`.
- [ ] You: review the THESIS diff, push to main (site auto-deploys).

  ```bash
  cd ~/Projects/THESIS
  git show dc30449          # review the diff
  git push origin main
  ```

- [ ] You: check thesis.do/galley renders, click every link (Download for
      Mac, View source, the kept cross-link, the homepage card).

## Phase 1, this week (you, about 2 hours)

- [ ] Apple Developer: confirm membership is active. Then in
      `project.yml`, add your team ID under `settings.base`:

  ```yaml
  settings:
    base:
      DEVELOPMENT_TEAM: <TEAMID>
  ```

  Note: `project.yml` still has `MARKETING_VERSION: "1.0.0"`, one behind
  the `v1.1.0` tag just pushed. Bump it to `1.1.0` in the same edit, so
  the archive you submit matches the release.

  ```bash
  xcodegen generate
  xcodebuild -project Galley.xcodeproj -scheme Galley -configuration Release \
    -archivePath build/Galley.xcarchive archive
  ```

- [ ] Notarize the DMG. Exact commands are in
      [DISTRIBUTION.md](../DISTRIBUTION.md) section 1:

  ```bash
  xcodebuild -exportArchive -archivePath build/Galley.xcarchive \
    -exportPath build/export -exportOptionsPlist docs/ExportOptions-developer-id.plist
  xcrun notarytool submit build/export/Galley.app --keychain-profile galley --wait
  xcrun stapler staple build/export/Galley.app
  ./scripts/make-dmg.sh build/export/Galley.app
  ```

  Then attach the notarized DMG to the `v1.1.0` GitHub release (it
  currently only has the unsigned preview zip):

  ```bash
  gh release upload v1.1.0 build/Galley-1.1.0.dmg
  ```

  Update the landing page Download link in `site/index.html` (and the
  THESIS `app/galley` page) to point at the DMG once it is attached.

- [ ] Submit the Homebrew cask. The name `galley` was verified unclaimed
      as of 2026-07, per [DISTRIBUTION.md](../DISTRIBUTION.md):

  ```bash
  brew bump-cask-pr --version 1.1.0 galley
  ```

- [ ] App Store Connect: create the app record "Galley, Markdown Reader".
      Upload the archive from Xcode Organizer, paste the copy from
      [docs/launch/appstore/metadata.md](appstore/metadata.md), upload the
      six `appstore-*.png` screenshots listed there, submit with the
      review notes (already included verbatim in that file).
- [ ] Create a Product Hunt draft using
      [docs/launch/producthunt/COPY.md](producthunt/COPY.md). Schedule for
      Tuesday or Wednesday, 12:01 AM Pacific.

## Phase 2, launch day

- [ ] PH goes live. Post the maker comment from `COPY.md` immediately.
- [ ] Show HN: title "Show HN: Galley, an open-source Markdown reader for
      the Mac." First comment condenses the maker story, links GitHub
      first.
- [ ] r/macapps post, X/Bluesky thread with the hero screenshot and the
      one-sentence name story from LAUNCH.md section 1.
- [ ] Reply to everything for six hours. File real bugs as GitHub issues
      as they come in.

## Phase 3, the week after

- [ ] Ship a v1.1.x with the two most-requested small fixes. Announce in a
      PH comment and in the release notes ("the reader reads its
      readers").
- [ ] Write the build story for thesis.do: the research, the moat, the
      name.

## What is already done (this session)

- URL sweep: every `thesis-labs/galley` reference replaced with
  `JessieSalas/galley` in README.md, CONTRIBUTING.md, DESIGN.md,
  docs/appstore/metadata.md, Galley/App/GalleyCommands.swift,
  Galley/Resources/Samples/Welcome.md, Galley/Views/SettingsView.swift.
  `site/index.html` was already correct. The phrase "transfer to a
  thesis-labs org later" in LAUNCH.md was left alone, and LAUNCH.md's own
  reference to the `thesis-labs/galley` URL pattern (its section 8
  instructions to future agents) was left as written.
- README upgraded: hero and themes screenshots, an Install section
  (Releases download, build from source, App Store coming soon), and an
  em dash sweep through the prose.
- `docs/launch/appstore/metadata.md` written per LAUNCH.md section 7.
- `docs/launch/producthunt/COPY.md` written per LAUNCH.md section 6.
- Debug build verified: `BUILD SUCCEEDED`.
- Release build verified: `BUILD SUCCEEDED`. Packaged as an unsigned
  preview zip, since no `DEVELOPMENT_TEAM` is configured yet.
- `.gitignore` gained a `build-release/` entry so the 348 MB unsigned
  Release build products are not tracked in git history.
- Repo published: https://github.com/JessieSalas/galley, public, with
  topics macos, markdown, swift, swiftui, markdown-viewer, reader.
- Release published: https://github.com/JessieSalas/galley/releases/tag/v1.1.0,
  with the unsigned preview zip attached.
