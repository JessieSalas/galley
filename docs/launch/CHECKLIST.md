# Launch checklist

Status as of 2026-07-24. Source plan: [LAUNCH.md](../LAUNCH.md) section 9.

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
  https://github.com/JessieSalas/galley/releases/tag/v1.1.0 — signed,
  notarized, and stapled (`Galley-1.1.0.zip` and `Galley-1.1.0.dmg`),
  verified with `spctl` (accepted, source=Notarized Developer ID) and
  `stapler validate`. The old unsigned preview zip was removed.
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
- **Shipped v1.1.1.** Ran the real customer install from a fresh download
  of thesis.do's actual production DMG (quarantine flag set, like a real
  Safari download): zero Gatekeeper warnings, clean drag-to-Applications
  install. Along the way, found that `.md` opened in Xcode by default on
  this machine (the exact problem Galley exists to fix), and that the
  documented Finder "Change All" method only covers the one extension you
  right-click, not all 5 Galley supports. Added a one-click "Set Galley as
  Default" button (`NSWorkspace.setDefaultApplication(at:toOpen:)`) that
  covers the whole UTI at once — tested against a real signed debug build
  first since this API is documented to throw a permission error on
  sandboxed apps (Galley is sandboxed even in the direct-distribution
  build); it worked cleanly, verified by opening a `.markdown` file that
  had never been touched. Built, signed, notarized (both the app and the
  DMG), stapled, and verified all over again for 1.1.1 specifically.
  Live: https://github.com/JessieSalas/galley/releases/tag/v1.1.1 and
  thesis.do/galley (old 1.1.0 DMG removed from both, confirmed 404).
  `docs/launch/homebrew-cask-galley.rb` updated to 1.1.1's sha256 (also
  fixed a real syntax bug it had, `>= :sonoma` isn't valid Ruby DSL —
  should be `:sonoma`).

## Blocked on you — one thing, then one optional one

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

- [x] ~~Notarize the DMG~~ — done (see above; carried forward through
      1.1.1). The DMG container itself couldn't be separately code-signed
      (that private key only lives inside Xcode's own automatic-signing
      session, not reachable from a bare `codesign` call) — Apple's
      notarization docs say this is fine for disk images, and the notary
      service accepted it regardless. Homebrew submission is still
      blocked on repo stars, not signing (see the cask file's own header
      for the exact gate).

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
