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

## Blocked on you — two small things, then two bigger optional ones

- [ ] **App Store Connect → App Review Information → Contact Information.**
      Name and email are filled; the **Phone number** field is required and
      must be in `+countrycode...` format, which I don't have and won't
      fabricate. This is also why the section wouldn't save no matter how
      many times I retried (a persistent 409 from the server — confirmed via
      network inspection, not a fluke — traces directly back to this missing
      required field). Takes 20 seconds:
      https://appstoreconnect.apple.com/apps/6794124447/distribution/macos/version/inflight
      → scroll to App Review Information → fill Phone → Save.

- [ ] **Screenshots, both platforms.** I hit a real, intentional tool
      boundary, not a bug: neither the file-upload tool nor computer-use can
      drive a native macOS file picker spawned from Chrome (browsers are
      permanently read-tier for computer-use; file uploads require files the
      user explicitly shared with the session). This needs your hands:
      - **App Store Connect**, same page as above, top of the page: drag
        the 6 files from `docs/launch/screenshots/appstore-1-hero.png`
        through `appstore-6-terminal.png` onto the screenshot well.
      - **Product Hunt**: the draft is filled through the Main Info step
        (name, tagline, links, tags, description, open-source toggle, the
        maker comment) at https://www.producthunt.com/posts/new/submission
        — click "Next step: Images and media" and drag in
        `docs/launch/producthunt/ph-0-tagline.png` through `ph-6.png` plus
        `ph-icon-240.png`, per the order in
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

- [ ] **Push THESIS.** Two commits sitting locally, reviewed and ready:

  ```bash
  cd ~/Projects/THESIS
  git log origin/main..HEAD --oneline   # 7623b96 font, 6565c8f tagline
  git push origin main
  ```

## Phase 2, launch day (once the above is done)

- [ ] Submit the App Store Connect app for review ("Add for Review").
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
