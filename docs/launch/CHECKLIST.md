# Launch checklist

Status as of 2026-07-23, end of session. Source plan: [LAUNCH.md](../LAUNCH.md) section 9.

## Done

- Security audit: no kept code, kept data, or secrets anywhere in the public
  repo or its git history. Two real issues found and fixed: a committed
  scratchpad symlink, and a ReDoS-class regex in the edit-mode syntax
  highlighter (verified with real benchmarks before and after).
- Font: Galley's own display face is Fraunces, not kept's Bricolage
  Grotesque, everywhere (in-app default theme, both landing pages, all
  screenshots).
- Tagline changed to "Markdown, beautifully typeset." everywhere, including
  every screenshot with it baked into the pixels.
- The screenshot tool itself (`scripts/snapshot.swift`) got two real fixes:
  it no longer depends on the calling session's ambient display scale
  (was silently non-deterministic), and it now exposes `scale`/`measure`
  as job options.
- thesis.do is live. Pushed and verified directly: thesis.do/galley
  renders correctly, the homepage shows kept and galley side by side, both
  intact.
- Repo public: https://github.com/JessieSalas/galley. Release live:
  https://github.com/JessieSalas/galley/releases/tag/v1.1.0 (unsigned
  preview zip attached; notarized DMG still to come, see below).
- Git history rewritten: every commit message's "Co-Authored-By: Claude"
  trailer stripped (main and the v1.1.0 tag force-pushed to the rewritten
  history; verified zero trailers remain and the release asset survived).
  All commits from here on are plain, no AI attribution.
- Apple signing pipeline verified end to end under **Thesis Labs LLC**
  (Team ID `922HAZ57Q8`, wired into `project.yml`): archived, exported for
  App Store Connect (real "Cloud Managed Apple Distribution" cert,
  Xcode auto-generated it live), exported Developer ID (real "Developer ID
  Application: Thesis Labs LLC" cert, also auto-generated), and **uploaded
  build 1.1.0 straight to App Store Connect** — all via Xcode's already
  authenticated account session, no password ever touched.
- App Store Connect: app record created ("Galley, Markdown Reader",
  bundle ID `do.thesis.galley`). General metadata saved and verified
  server-side (promotional text, full description, keywords, support/
  marketing URLs, version, copyright). Build 1.1.0 (1) attached.
- **App Store Connect submitted for review.** Filled in everything that
  was actually still missing beyond the version page: Category
  (Productivity), Content Rights (no third-party content), Age Ratings
  (answered the full 7-step questionnaire, calculated rating 4+), App
  Privacy (added a real privacy policy page at thesis.do/privacy and
  answered the data-collection questionnaire: data not collected),
  and Pricing and Availability (free, all 175 countries). Clicked "Add for
  Review" then "Submit for Review" — confirmed: **1 Item Submitted,
  status Waiting for Review**, up to 48 hours.
- THESIS pushed: the font, tagline, and new privacy-policy commits are on
  `origin/main`, so thesis.do is redeploying live.

## Blocked on you — one thing, then two bigger optional ones

- [ ] **Product Hunt screenshots.** Still empty ("Thumbnail is required",
      "Image is required" on the Images and media step) — App Store
      Connect's screenshots made it in, but Product Hunt's didn't. I tried
      a workaround (pasting public `raw.githubusercontent.com` URLs into
      PH's "Paste a URL" field instead of drag-and-drop, since the file
      picker is a wall I already know I can't drive) — it triggered a
      clipboard-permission prompt in the browser extension's side panel
      that only you can approve, and froze the tab until I reloaded the
      page. I'm not going to keep poking at that; it needs your hands,
      same as before:
      https://www.producthunt.com/posts/new/submission → Images and media
      → drag in `docs/launch/producthunt/ph-0-tagline.png` through
      `ph-6.png` plus `ph-icon-240.png` (thumbnail), per the order in
      [COPY.md](producthunt/COPY.md).

- [ ] **Notarize the DMG** (optional — only needed for direct/Homebrew
      distribution outside the App Store). Requires an App Store Connect
      API key, which is its own account-level grant
      (Users and Access → Integrations → App Store Connect API) that needs
      your explicit action to enable — I stopped at that page rather than
      requesting API access on your behalf. Once you have a key:

  ```bash
  xcrun notarytool store-credentials galley \
    --key ~/path/to/AuthKey_XXXX.p8 --key-id XXXX --issuer-id XXXX
  cd ~/Projects/galley
  xcodebuild -exportArchive -archivePath build/Galley.xcarchive \
    -exportPath build/export-developer-id \
    -exportOptionsPlist docs/ExportOptions-developer-id.plist -allowProvisioningUpdates
  xcrun notarytool submit build/export-developer-id/Galley.app --keychain-profile galley --wait
  xcrun stapler staple build/export-developer-id/Galley.app
  ./scripts/make-dmg.sh build/export-developer-id/Galley.app
  gh release upload v1.1.0 Galley-1.1.0.dmg
  ```

  Then finish the Homebrew cask (`docs/launch/homebrew-cask-galley.rb` has
  the template; needs the notarized zip's sha256) and submit:
  `brew bump-cask-pr --version 1.1.0 galley`.

## Phase 2, launch day (once the above is done)

- [x] Submit the App Store Connect app for review ("Add for Review") — done, waiting on Apple.
- [ ] Schedule and post Product Hunt: Tuesday or Wednesday, 12:01 AM
      Pacific. Post the maker comment the moment it's live.
- [ ] Show HN: "Show HN: Galley, an open-source Markdown reader for the
      Mac." Link GitHub first.
- [ ] r/macapps, X/Bluesky with the hero screenshot and the one-sentence
      name story from LAUNCH.md section 1.
- [ ] Reply to everything for six hours. File real bugs as GitHub issues
      as they land.

## Phase 3, the week after

- [ ] Ship a v1.1.x with the two most-requested small fixes. Announce in a
      PH comment and the release notes ("the reader reads its readers").
- [ ] Write the build story for thesis.do: the research, the moat, the name.
