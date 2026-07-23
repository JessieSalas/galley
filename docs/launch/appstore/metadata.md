# App Store metadata: Galley

## Name
Galley, Markdown Reader

## Subtitle (30 chars)
The missing Markdown reader

## Category
Productivity (secondary: Developer Tools)

## Price
Free

## Promotional text (170 chars)
Double-click a Markdown file. Get a typeset page, not source code. Read-only
by design, live to changes, beautiful in five themes. Free and open source.

## Description

Markdown became the paper of the AI age. Agents write plans in it. Models
answer in it. Your disk is filling with documents that were meant to be read.
And the Mac still opens them as raw text in the wrong app. Galley is the
missing reader.

READ, DON'T RISK
Galley opens every document read-only, every time. No cursor. No accidental
edits. Nothing to mangle during a screen share. When you need to fix a typo,
edit mode is one keystroke away, and leaving it is just as fast.

EVERYTHING RENDERS
Tables, task lists, footnotes, callouts. Code with real syntax color. Mermaid
diagrams. Math. Front matter as a tidy card instead of a wall of dashes.
• GitHub-flavored Markdown: tables, task lists, footnotes, callouts
• Syntax-highlighted code with one-click copy
• Mermaid diagrams, themed to match your appearance
• LaTeX math (KaTeX)
• YAML front matter as a tidy metadata card

MADE FOR THE AI ERA
Point it at a file your agent is still writing. Galley follows along quietly
and keeps your place. A small pill says updated. That is the whole ceremony.
• Copy for AI: grab the raw source with a file path header
• Token estimates alongside words and reading time
• Recognizes CLAUDE.md, AGENTS.md, and friends

A REAL MAC APP
Five themes: Thesis, Manuscript, Studio, Terminal, Editorial. Each with its
own light and dark. Fonts, colors, and accents are yours to change, and the
defaults are the best ones.
• Outline sidebar, find, presentation mode
• Quick Look: press Space in Finder for the same typeset preview
• Export PDF or HTML, print properly
• Sandboxed. No account. No sync. No telemetry. Free, and open source under MIT.

Galley is free and open source, from Thesis Labs.

## Keywords (100 chars)
markdown,md,reader,viewer,preview,mermaid,katex,readme,claude,agent,quick look,editor,github,notes

## Support URL
https://github.com/JessieSalas/galley/issues

## Marketing URL
https://thesis.do

## Privacy
Data not collected. (No tracking, no identifiers, no analytics.)

## Review notes (copied verbatim from docs/DISTRIBUTION.md)

> Galley is a read-only Markdown viewer. The `com.apple.security.network.client`
> entitlement exists because WKWebView's out-of-process networking requires it
> even for purely local content, and because documents may reference remote
> images (user-disableable in Settings → Privacy). All rendering libraries are
> bundled; the app makes no network requests of its own, has no analytics, and
> no accounts. The folder-access panel appears only when a document references
> local images outside its own file, and the grant is stored as a
> security-scoped bookmark so users are never re-asked.

## Screenshots to upload (2880×1800)

1. `docs/launch/screenshots/appstore-1-hero.png`, Thesis theme, front-matter card and opening prose
2. `docs/launch/screenshots/appstore-2-code-dark.png`, Ink theme, Swift and Python code with real syntax color
3. `docs/launch/screenshots/appstore-3-themes.png`, all five themes side by side, light and dark
4. `docs/launch/screenshots/appstore-4-diagrams.png`, a Mermaid flowchart and a rendered table
5. `docs/launch/screenshots/appstore-5-math.png`, inline and display math, plus callout cards
6. `docs/launch/screenshots/appstore-6-terminal.png`, Terminal theme, long-form prose with a blockquote
