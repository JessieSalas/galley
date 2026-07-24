# Galley launch bible

Everything needed to ship Galley publicly. Copy is final unless marked draft.
Voice rules for every public word: short declarative sentences, no hype words,
no em dashes anywhere, no exclamation points, lowercase product names (galley,
kept) in brand surfaces, Title Case "Galley" in App Store and GitHub contexts.
Print metaphors welcome. Say less.

---

## 1. The name: Galley, now with conviction

The question was whether Galley is a placeholder or the name. It is the name.

**The case.** Before a book exists, its manuscript is set in type and printed
once, plainly, so people can read it. Printers call that copy a galley. It is
the read-only edition. That is exactly what this app does to a Markdown file.
The metaphor is not adjacent. It is the product.

It also sits right in the Thesis family register: thesis, the argument. kept,
what you keep. galley, what you read. All quiet, common, print-culture nouns
that reward a second look. "kept" required a beat of thought too. That beat is
the brand.

**The diligence.** Two research passes (July 2026) swept the alternatives. The
print-culture namespace is brutally crowded, which makes Galley's clearance
rare luck:

| Candidate | Verdict |
| --- | --- |
| Ream | Taken. "Ream, Markdown Reader" already on the App Store. Fatal. |
| Vellum | Taken. The beloved Mac book-formatting app. |
| Folio, Imprint, Typeset, Manuscript, Octavo, Flyleaf, Deckle, Offprint, Broadsheet | All taken by live products, several in-category. |
| Proof | Beautiful meaning, hopelessly generic namespace, many apps. |
| Quire | Taken. quire.io project management. |
| Colophon, Recto, Preprint, Lectern, Sheaf | Risky. Live in-category or open source collisions. |
| **Galley** | Clear. No markdown, writing, or reading app on any platform. Bare name on the App Store held only by food apps, solved by the standard listing form. Homebrew cask `galley` unclaimed. |

**The honest weakness.** Most people hear "galley" and think of a ship's
kitchen. Fine. The subtitle does the teaching in four words, the story does it
in one sentence, and nobody who learns the meaning forgets it. Names that
carry a small story outperform names that carry none.

Verdict: keep Galley. Stop treating it as provisional. Tell the story
everywhere, once, briefly.

The one-sentence story, canonical form:

> In publishing, a galley is the typeset proof of a manuscript, printed
> plainly so it can simply be read. That is this app.

---

## 2. Copy blocks (canonical, reuse everywhere)

**Tagline (primary):**
> Markdown, beautifully typeset.

**Tagline (support):**
> A quiet, beautiful reader for the files the AI age keeps writing.

**Hero:**
> Double-click a Markdown file. Get a page, not a pane of source code.

**The why:**
> Markdown became the paper of the AI age. Agents write plans in it. Models
> answer in it. Your disk is filling with documents that were meant to be
> read. And the Mac still opens them as raw text in the wrong app. Galley is
> the missing reader.

**Read-only:**
> Galley opens every document read-only, every time. No cursor. No accidental
> edits. Nothing to mangle during a screen share. When you need to fix a typo,
> edit mode is one keystroke away, and leaving it is just as fast.

**Everything renders:**
> Tables, task lists, footnotes, callouts. Code with real syntax color.
> Mermaid diagrams. Math. Front matter as a tidy card instead of a wall of
> dashes.

**Live view:**
> Point it at a file your agent is still writing. Galley follows along
> quietly and keeps your place. A small pill says updated. That is the whole
> ceremony.

**Themes:**
> Five themes: Thesis, Manuscript, Studio, Terminal, Editorial. Each with its
> own light and dark. Fonts, colors, and accents are yours to change, and the
> defaults are the best ones.

**Trust:**
> No account. No sync. No telemetry. Free, and open source under MIT.

**The kept echo (for thesis.do only):**
> The best software doesn't ask for your attention. Galley doesn't even ask
> for your keyboard.

---

## 3. thesis.do (site repo: ~/Projects/THESIS, auto-deploys on push to main)

### 3a. New page: `app/galley/page.tsx` at thesis.do/galley

Structure mirrors the site system (eyebrows, statements, hairlines, spectral
restraint). Sections, in order:

1. **Hero.** Eyebrow: `GALLEY · A READER`. Statement (display font):
   "Markdown, beautifully typeset." Lede: the hero line plus the one-sentence
   name story. Actions: `Download for Mac` (GitHub releases link),
   `View source` (GitHub), and later `App Store` when live.
2. **Product image.** The hero screenshot, full width, hairline border,
   rounded corners, on cream.
3. **Why.** Statement: "The paper of the AI age." Body: the why block plus
   the read-only block.
4. **What renders.** The everything-renders block plus the live-view block,
   with the dark screenshot.
5. **Themes.** The themes block with the theme-grid image.
6. **Colophon.** Trust block. "Open source under MIT. Built by Thesis Labs."
   Link to kept: "It lives beside kept, software for the work of your life."

### 3b. Homepage: add galley beside kept

Match however kept is presented on the homepage (read page.tsx first). A
section or card: mark "galley" in the display font, tag line "the Markdown
reader", one sentence: "Every Markdown file, opened as a typeset page." Status
chip like kept's live dot if the pattern exists. Links: thesis.do/galley and
GitHub.

---

## 4. Landing page (standalone, ships in repo at site/index.html)

Single self-contained HTML file, hand-set CSS in the Thesis system (tokens
from the app's theme.css). No frameworks, no external requests, fonts
inlined or system-stack fallback. This same file can later be served at
galley.thesis.do if wanted; primary destination is thesis.do/galley (3a), so
this landing is the GitHub Pages / preview artifact and the design reference
for 3a. Structure identical to 3a with real screenshots. Footer: MIT, GitHub,
Thesis Labs, "Set in Bricolage Grotesque, Inter, and JetBrains Mono."

Design bar: this page should look like the app. Cream and ink, hairlines,
mono eyebrows, one spectral moment (the hr under the hero). Screenshots carry
the page; the words stay out of their way.

---

## 5. Screenshots (real product, no mockups)

Method: the app gains a debug env var `GALLEY_FRAME=x,y,w,h` that positions
the document window exactly. Window 1440x900 points on the 2x display gives
2880x1800 native pixels, the exact App Store size. Capture the full screen
via the automation tooling at native resolution, crop to the known window
rect, done. The window IS the product; no compositing, no fakery.

Shot list (file names canonical):

| # | File | Content | Theme/mode |
| --- | --- | --- | --- |
| 1 | shot-1-hero-thesis-light.png | Tour.md top: front-matter card + H1 + opening prose | Thesis light |
| 2 | shot-2-dark-code.png | Tour.md code section: swift + python blocks | Thesis dark |
| 3 | shot-3-themes-popover.png | Aa popover open over the page | Manuscript light |
| 4 | shot-4-diagrams.png | Mermaid flowchart + table section | Studio light |
| 5 | shot-5-edit-mode.png | Edit mode, syntax-highlighted source | Terminal dark |
| 6 | shot-6-sidebar-long.png | Outline sidebar open, long doc | Editorial light |

Post-processing for App Store: none needed if crops are exactly 2880x1800.
For Product Hunt gallery (1270x760): place each crop scaled onto a cream
(#F1ECE2) canvas with 48px margin and a one-line caption in Inter, ink color,
top-left, mono eyebrow style. Also produce PH first-slide with just the
tagline set large on cream with the app icon.
For the landing/thesis.do: use raw crops at 1440w webp/png.

---

## 6. Product Hunt packet (docs/launch/producthunt/)

- **Name:** Galley
- **Tagline (60 max):** The missing Markdown reader for the Mac
- **Links:** thesis.do/galley, GitHub repo, App Store (when live)
- **Topics:** Mac, Open Source, Productivity, Design Tools, Artificial Intelligence
- **Description (260 max):**
  > Every Markdown file opens as a quiet, typeset page. Read-only by design,
  > with a deliberate edit mode. Follows files your AI agents are still
  > writing. Five themes, Mermaid, math, and zero telemetry. Free and open
  > source.
- **First comment (maker story, post immediately at launch):**

  > Hi Product Hunt, I'm Jessie.
  >
  > Markdown quietly became the paper of the AI age. My agents write plans
  > in it, my tools log in it, half of what I read every day is a .md file.
  > And when I double-clicked one on my Mac, I got raw hash marks in
  > TextEdit, or Xcode taking ten seconds to show me source code.
  >
  > Every "viewer" I tried was secretly an editor. A cursor in a file I only
  > wanted to read. Spell-check squiggles during screen shares. So we built
  > the thing that was missing: a reader.
  >
  > Galley opens every Markdown file as a typeset page, instantly. It is
  > read-only on purpose. It follows files your agents are still writing and
  > keeps your place while they work. There are five themes with real
  > typography, and everything renders: tables, callouts, Mermaid, math.
  >
  > The name comes from publishing. A galley is the typeset proof of a
  > manuscript, printed plainly so it can simply be read. That felt right.
  >
  > It is free, open source, and sandboxed, with no telemetry. I would love
  > to know what you read with it.

- **Gallery:** PH-framed versions of shots 1 through 6 plus the tagline slide.
  Icon at 240x240 from the appiconset.
- **Launch timing:** Tuesday or Wednesday, 12:01 AM Pacific. Clear your
  morning to reply to every comment for the first 6 hours.

---

## 7. Mac App Store packet (docs/launch/appstore/)

- **Name:** Galley, Markdown Reader  (bare "Galley" is held; this form is standard)
- **Subtitle (30):** The missing Markdown reader
- **Promotional text (170):**
  > Double-click a Markdown file. Get a typeset page, not source code.
  > Read-only by design, live to changes, beautiful in five themes. Free and
  > open source.
- **Description:** rewrite of docs/appstore/metadata.md in the voice rules
  (no em dashes, no bullets-with-dashes; use the copy blocks in section 2,
  organized under the same headers). Keywords unchanged. Privacy: data not
  collected.
- **Screenshots:** shots 1 through 6 at 2880x1800.
- **Review notes:** already drafted in docs/DISTRIBUTION.md; include verbatim.
- **Category:** Productivity; secondary Developer Tools. Price: Free.

---

## 8. Open source publishing (GitHub)

Repo: github.com/JessieSalas/galley (transfer to a thesis-labs org later is
one click; do not block launch on org creation).

Steps (agents do the mechanical parts):
1. Update every `thesis-labs/galley` URL in the repo (README, app Help menu,
   SettingsView About links, ACKNOWLEDGEMENTS, DISTRIBUTION) to the real URL.
2. `gh repo create galley --public --source . --push` with description
   "A quiet, beautiful Markdown reader for the Mac. Read-only by design."
   and homepage thesis.do/galley. Topics: macos, markdown, swift, swiftui,
   markdown-viewer, reader, open-source, wkwebview.
3. Add screenshots to README (hero + dark) once captured.
4. Release v1.1.0: tag, GitHub release with notes, attach the unsigned dev
   DMG as a preview artifact, note that the notarized build follows once the
   Developer ID certificate is in place.

---

## 9. Launch strategy, step by step

**Phase 0, today (agents + you):**
- [ ] agents: screenshots captured and processed
- [ ] agents: GitHub repo public, links consistent, README with images
- [ ] agents: landing page in repo, thesis.do route + homepage card committed
      to the THESIS repo locally
- [ ] you: review the THESIS diff, push to main (site auto-deploys)
- [ ] you: check thesis.do/galley renders, click every link

**Phase 1, this week (you, ~2 hours):**
- [ ] Apple Developer: confirm membership active; in project.yml add your
      DEVELOPMENT_TEAM, `xcodegen generate`, archive Release
- [ ] Notarize the DMG (docs/DISTRIBUTION.md has exact commands), attach to
      the GitHub release, update the landing Download link
- [ ] Submit the Homebrew cask (name `galley` verified unclaimed)
- [ ] App Store Connect: create the app record "Galley, Markdown Reader",
      upload the archive from Xcode Organizer, paste the packet copy, upload
      the 6 screenshots, submit with the review notes
- [ ] Create a Product Hunt draft with the packet; schedule Tuesday 12:01 AM PT

**Phase 2, launch day:**
- [ ] PH goes live; post the maker comment immediately
- [ ] Show HN: title "Show HN: Galley, an open-source Markdown reader for
      the Mac", first comment condenses the maker story, links GitHub first
- [ ] r/macapps post, X/Bluesky thread with the hero screenshot and the
      one-sentence name story
- [ ] Reply to everything for six hours; file real bugs as GitHub issues live

**Phase 3, the week after:**
- [ ] Ship a v1.1.x with the two most-requested small fixes; announce in a
      PH comment and release notes ("the reader reads its readers")
- [ ] Write the build story for thesis.do (the research, the moat, the name)

**What only you can do, summarized:** push THESIS to main, Apple Developer
team + notarization credentials, App Store Connect account actions, Product
Hunt scheduling, social posting.
