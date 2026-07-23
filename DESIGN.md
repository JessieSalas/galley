---
title: Galley — Design Document
author: Thesis Labs
date: 2026-07-22
status: v1.0
---

# Galley

**A quiet, beautiful reader for Markdown. The missing system app.**

Open source, from [Thesis Labs](https://thesis.do). This document is the founding
design doc: why Galley exists, what it is, what it refuses to be, and how it's built.

## The thesis

Markdown became the paper of the AI age — and the Mac never got a way to read it.

Every LLM emits Markdown by default. Coding agents use it as working memory:
`CLAUDE.md`, `AGENTS.md`, `plan.md`, `report.md`. The web is being re-served in it
for agents (`llms.txt`, "Copy page as Markdown"). Chat apps export to it. Notes
ecosystems live in it. Disks are filling with `.md` files **written by machines,
for humans to read** — and when you double-click one on a Mac in 2026, you get:

- **TextEdit** — raw hash marks and pipe tables. A ransom note.
- **Xcode** — a 30 GB IDE that takes ten seconds to show you unstyled source.
- **Typora / iA Writer** — an *editor*: a blinking caret in a file you only
  wanted to read, and a real chance of mangling it during a screen share.
- **Obsidian** — a vault picker instead of your file.
- **Quick Look** — plain text, because Apple never shipped a Markdown renderer.
  Twenty-two years after the format appeared.

Every incumbent monetizes *writing*, so *reading* is always a degraded side-mode.
The category research (see below) found a dozen near-identical micro-viewers on
the App Store — ad-ridden, generic, unloved — and one respected previewer (Marked)
that is positioned for writers proofing drafts and has moved to subscription.

**The open position is the missing system app: Preview.app for Markdown.**
The app you *set as your default handler* and recommend by name, the way Preview
owns PDF and The Unarchiver owns archives. Read-only is not a limitation to
apologize for — it is the entire positioning:

> A reader never puts a cursor in your file. It can never mangle a document
> during a screen share. It opens instantly because it does one thing.

## The name

**Galley.** In publishing, a *galley* is the typeset, read-only proof of a
manuscript — the version sent to readers before printing. That is literally what
this app does to a Markdown file: your plain-text manuscript, beautifully typeset,
look-don't-touch.

Lowercase-friendly, one word, warm, print-culture — it sits naturally beside
*kept* in the Thesis Labs family. Collision-checked against the App Store, GitHub,
and trademarks (2026-07): clear in category. App Store listing form:
**"Galley — Markdown Reader."**

## What Galley is (and refuses to be)

**Is:** the fastest, most beautiful way to *read* a Markdown file on a Mac.
Double-click → typeset page. Screen-share-proof. Agent-aware.

**Refuses to be:** an editor, a notes app, a vault, a sync service, a subscription.
No accounts, no telemetry, no network calls except images the document itself
references (and you can turn those off).

## Product principles

1. **Paper, not app.** The window is a page. Chrome recedes; typography leads.
2. **Zero-config beauty.** The defaults must be the best-looking; settings exist
   to accommodate, not to rescue.
3. **Never touch the file.** Read-only at the architecture level (viewer document
   role; no write path exists in the code).
4. **Respect the machine.** Native app, small footprint, instant launch, no Electron.
5. **The AI era is the reader's era.** Live-follow files agents are still writing;
   render front matter as metadata, not noise; count tokens, not just words.

## Feature specification (v1)

### Reading surface
- Full CommonMark + GFM: tables, task lists, strikethrough, autolinks, footnotes
- GitHub-style callouts (`> [!note]`, `[!tip]`, `[!important]`, `[!warning]`, `[!caution]`)
- Syntax-highlighted code fences (highlight.js, ~40 languages + Swift/Docker/nginx),
  language badge, hover **copy** button per block
- **Mermaid** diagrams in ```` ```mermaid ```` fences, themed to match appearance
- **KaTeX** math: `$inline$`, `$$display$$`, ```` ```math ```` fences
- YAML **front matter** rendered as a metadata card (tags become pills); raw wall
  of dashes never shown
- Smart typography (quotes, dashes, ellipses) — toggleable
- Images: local (relative paths) and remote; remote can be blocked in Privacy
- Footnotes, heading anchors (hover ¶ copies `#section` link), spectral `<hr>`

### Appearance
- **Paper** (warm cream + ink) and **Ink** (warm near-black) themes, or **System**
- Typeface: **Default** (Bricolage Grotesque display + Inter body), **Serif**
  (New York), **Mono** (JetBrains Mono), **System** (SF)
- Text size (⌘+ / ⌘− / ⌘0), line width (narrow / normal / wide), all live
- The Thesis spectral gradient appears in exactly three places: under the
  document's opening H1, in horizontal rules, and on link hover. Restraint is the brand.

### The AI angle
- **Live view**: kqueue file watching; re-renders on change, survives atomic
  saves (vim/VS Code rename dance), keeps your scroll position; if you're at the
  bottom, **follows the tail** as an agent writes — a quiet "updated" pill instead
  of a jarring reload
- **Copy for AI**: raw source with file-path context header, ⌘⇧C
- **Token estimate** (~chars/4) alongside words and reading time in the Info popover
- **Identity badges**: `CLAUDE.md` → "Agent instructions", `AGENTS.md`, `SKILL.md`,
  `README.md` recognized in the window subtitle

### Mac citizenship
- True document-based viewer app: Finder double-click, Open With, drag to Dock,
  Open Recent, window restoration, per-document scroll memory
- **Outline sidebar** (⌘⇧O toggle? — standard ⌃⌘S) from headings, click to jump,
  tracks reading position
- Find in document (⌘F)
- **Presentation mode** (⌘⇧P): full screen, larger measure-tuned type, zero chrome
- Export **PDF** (paginated via print pipeline, or continuous), Export **HTML**,
  Print (⌘P) with proper print CSS
- **Quick Look extension**: press Space in Finder, get the same typeset page
  (static: no scripts/diagrams; the app is the full experience)
- Sandboxed with the minimal entitlement set; opening a doc via Launch Services
  needs zero dialogs. Local images in other folders trigger a one-time,
  pre-pointed folder-access grant, remembered via security-scoped bookmark

### Settings (⌘,)
- **Reading**: live reload, follow tail, restore scroll position, smart
  typography, front-matter display
- **Appearance**: theme, typeface, text size, line width (defaults; per-window
  zoom layers on top)
- **Privacy**: load remote images (off = compiled WKContentRuleList blocks all
  remote loads), granted-folders list with revoke
- **Default app**: guided "make Galley your default Markdown app" (Finder
  Get Info → Change All; sandboxed apps cannot set this programmatically — a
  button that fails silently is worse than honest guidance)

## Architecture

| Area | Decision | Why |
| --- | --- | --- |
| Shell | SwiftUI `DocumentGroup(viewing:)` + AppKit where it counts | Purpose-built for read-only viewers; Finder/recents/restoration free |
| Rendering | WKWebView + bundled JS (markdown-it 14.3, highlight.js 11.11, mermaid 11.16, KaTeX 0.18.1) | Mermaid requires JS; category leaders all render HTML; print/PDF free |
| Bundling | esbuild → single `reader.bundle.js`, all assets local, no CDN ever | Sandbox, offline, App Review hygiene |
| Doc assets | Custom `doc-asset://` WKURLSchemeHandler | Serves sibling images under security scope; avoids `loadFileURL` single-grant lock |
| Live reload | `DispatchSource` kqueue on `O_EVTONLY` fd; on `.rename/.delete` re-open with retry; 120 ms debounce | Only watcher that works with a single-file sandbox grant; survives atomic saves |
| File type | Imported UTI `net.daringfireball.markdown` (md/markdown/mdown/mkdn/mkd), role Viewer, rank **Alternate** | The UTI Apple is adopting in OS 27; never hijack the user's default |
| Entitlements | sandbox + user-selected read-only + bookmarks.app-scope + network.client. Nothing else. | Every extra entitlement is a rejection vector |
| Print | `printOperation(with:)` + `printOp.view.frame = webView.bounds` before run | macOS 26 (Tahoe) crash workaround, verified |
| Quick Look | Data-based `QLPreviewProvider`; markdown-it inside JavaScriptCore → static HTML | Same renderer DNA; no web process; fast; images politely hidden |

Deployment target: macOS 14. Bundle ≈ 10 MB (mermaid is 3.4 MB of it).

## Brand application

From the Thesis Labs system (thesis.do):

- **Surfaces**: cream `#F1ECE2`, raised `#F8F5EE`; ink `#15140E`, secondary
  `#4A4639`, muted `#8E8879`; hairlines `#D9D3C6` / `#C3BCAC`
- **Ink theme** inverts to warm near-black `#17160F` with cream text `#ECE7DA`
- **Spectral** `#ff5d73 → #ffb454 → #36d6c3 → #6aa6ff → #b07bff`, used sparingly
- **Type**: Bricolage Grotesque (display), Inter (body), JetBrains Mono
  (code + eyebrows) — bundled as variable woff2
- **Voice**: mono uppercase eyebrows, hairline rules, calm motion
  (`cubic-bezier(0.2, 0.7, 0.2, 1)`), no gradients on surfaces
- **Syntax highlighting** uses the spectral family (darkened for paper,
  brightened for ink) — code looks like the brand

## Research summary (2026-07-22)

Full multi-agent research runs behind this doc. Key verified findings:

- No beloved read-only Markdown reader exists on Mac; the "job to be done" is
  quoted verbatim in the wild ("*I just want to double-click on the file and READ
  it… why is that so hard?*" — HN, 2026)
- Marked 2 → Marked 3 moved to subscription (June 2026); MacDown is abandoned
  (no Apple Silicon); Obsidian's vault-picker failure on stray files is a
  years-old open complaint; QLMarkdown's Homebrew cask is deprecated with a
  Sept 2026 disable date
- Apple declared `net.daringfireball.markdown` as the system Markdown UTI for
  the OS 27 cycle — the platform is finally acknowledging the format, with no
  reader to go with it
- A dozen 2024–2026 App Store micro-viewers validate demand and leave the
  trust/taste position empty
- All bundled libraries are MIT/BSD; versions pinned and verified against npm/GitHub

## Roadmap (post-v1)

- Folder as a browsable set (sidebar file tree, relative-link navigation between docs)
- Chat-transcript smart rendering (ChatGPT/Claude export shapes → conversation layout)
- Custom CSS themes (user stylesheet hook)
- `.mdx` tolerance mode
- Localizations

## Distribution

- **Open source**: MIT, `github.com/thesis-labs/galley` (or user's org)
- **Direct**: notarized DMG via `scripts/make-dmg.sh`
- **Mac App Store**: "Galley — Markdown Reader", free; metadata in `docs/appstore/`
- Claim the Homebrew cask name `galley` early — verified unclaimed
