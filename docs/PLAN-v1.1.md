# Galley v1.1 — Themes + Edit Mode (execution spec)

Two features, one repair. The moat stays: **Galley opens read-only, always.**
Edit mode is a deliberate, explicit state the user enters — never a cursor
waiting to happen.

---

## Part A — Theme engine (5 built-ins, light+dark each, customizable)

### Model (`Galley/Core/Themes.swift`, new)

```swift
struct ThemePalette: Codable, Equatable {
    var bg, bgHi, bgDeep, ink, ink2, ink3, muted, line, lineStrong: String // hex
    var accent, live: String
    var synRed, synAmber, synTeal, synBlue, synPurple, synComment: String
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case bricolage, inter, newYork, system, jetbrainsMono, sfMono
    var css: String { /* font stacks, e.g. newYork -> "ui-serif, 'New York', Georgia, serif" */ }
    var label: String { "Bricolage Grotesque", "Inter", "New York (serif)", "System (SF)", "JetBrains Mono", "SF Mono" }
}

struct GalleyTheme: Identifiable {
    let id: String, name: String, blurb: String
    let light: ThemePalette, dark: ThemePalette
    let displayFont: FontChoice, bodyFont: FontChoice, monoFont: FontChoice
    let headingWeight: Int          // 560...760
    let spectral: Bool              // rainbow accents (h1 bar, hr, link hover)
}

/// User overrides layered on a built-in, stored per theme id as JSON in
/// UserDefaults key "galley.themeOverrides.<id>".
struct ThemeOverrides: Codable, Equatable {
    var displayFont, bodyFont, monoFont: FontChoice?
    var headingWeight: Int?
    var spectral: Bool?
    var light: PaletteOverride?     // bg, ink, accent (hex strings, optional)
    var dark: PaletteOverride?
}
struct PaletteOverride: Codable, Equatable { var bg, ink, accent: String? }
```

`ThemeStore` (enum or final class): `builtIns: [GalleyTheme]`, `current() -> GalleyTheme`,
`overrides(for:)/setOverrides`, `resolved(variant: light|dark) -> ResolvedTheme`
(palette with overrides applied — when the user overrides `bg` or `ink`, derive
`bgHi/bgDeep/ink2/ink3/line/lineStrong` by blending toward the other pole so a
single color pick still looks designed; use simple sRGB lerp helpers).

### The five built-ins (exact values)

1. **thesis** — "Warm paper and ink. The house style." spectral **true**, weight 600,
   fonts bricolage/inter/jetbrainsMono.
   - light: bg `#F1ECE2` hi `#F8F5EE` deep `#EAE4D6` ink `#15140E` ink2 `#4A4639` ink3 `#403C31` muted `#8E8879` line `#D9D3C6` strong `#C3BCAC` accent `#3A6CC9` live `#1F8A7D`; syn `#C04A5E #9C6A1F #177A6E #3A6CC9 #7A51C7 #8E8879`
   - dark: bg `#17160F` hi `#1E1D14` deep `#121109` ink `#ECE7DA` ink2 `#C9C3B2` ink3 `#B5AF9E` muted `#8E8879` line `#353327` strong `#4A473A` accent `#8FBCFF` live `#36D6C3`; syn `#FF8A9A #FFC37A #5DE3D0 #8FBCFF #C9A2FF #7D7869`
2. **manuscript** — "A well-set book. Serif, quiet, no fireworks." spectral **false**, weight 650, fonts newYork/newYork/jetbrainsMono.
   - light: bg `#F9F5EC` hi `#FFFDF8` deep `#F0EADC` ink `#221E17` ink2 `#5A4F41` ink3 `#4A4136` muted `#93887A` line `#E2DACB` strong `#CFC5B2` accent `#A33B2E` live `#4A7A62`; syn `#B0503F #96702B #4A7A62 #4E6FA3 #7A5E93 #93887A`
   - dark: bg `#201B14` hi `#282219` deep `#17130D` ink `#EDE4D3` ink2 `#C9BDA6` ink3 `#B4A78F` muted `#8F8672` line `#3A342A` strong `#4E463A` accent `#E08D7D` live `#7FBF9E`; syn `#E08D7D #D9B36B #8FCDA9 #92AEDC #B79ED6 #8F8672`
3. **studio** — "Neutral, modern, gets out of the way." spectral **false**, weight 700, fonts system/system/sfMono.
   - light: bg `#FFFFFF` hi `#F6F7F8` deep `#EEF0F2` ink `#17181A` ink2 `#45484D` ink3 `#3A3D42` muted `#8A8F98` line `#E4E6EA` strong `#CBCFD6` accent `#3B72E8` live `#12A594`; syn `#D0435B #B0730C #0E8A74 #2F6BDF #7A4FD0 #8A8F98`
   - dark: bg `#131417` hi `#1B1D21` deep `#0D0E10` ink `#E8EAED` ink2 `#B5BAC3` ink3 `#9BA1AB` muted `#7E838C` line `#2A2D33` strong `#3D4149` accent `#7AA5FF` live `#4ADFC4`; syn `#FF7B93 #FFC069 #4ADFC4 #82AFFF #BB9AF7 #7E838C`
4. **terminal** — "Everything in mono. For people who live in one." spectral **false**, weight 700, fonts jetbrainsMono ×3.
   - light: bg `#F4F4F0` hi `#FBFBF8` deep `#E9E9E2` ink `#1A1D1A` ink2 `#46504A` ink3 `#3B443E` muted `#7E877F` line `#DBDBD2` strong `#C2C4B8` accent `#157F5B` live `#157F5B`; syn `#C25450 #9A7420 #157F5B #3B6FB4 #8455B7 #7E877F`
   - dark: bg `#0D120E` hi `#141B16` deep `#080C09` ink `#D6E5D8` ink2 `#A3B8A7` ink3 `#8CA391` muted `#6F8273` line `#243026` strong `#35453A` accent `#48E5A3` live `#48E5A3`; syn `#FF7E79 #E5C07B #56D6AD #61AFEF #C678DD #6F8273`
5. **editorial** — "High contrast, tight headlines, one red." spectral **false**, weight 760, fonts bricolage/inter/jetbrainsMono.
   - light: bg `#FFFEFB` hi `#F7F5F0` deep `#EFEBE3` ink `#0E0D0B` ink2 `#3E3B36` ink3 `#33302B` muted `#8C877E` line `#E6E2D9` strong `#CDC7BA` accent `#E23B2E` live `#12A594`; syn `#C93A32 #A06B14 #0F8A74 #2F62C4 #7648C8 #8C877E`
   - dark: bg `#151412` hi `#1D1C19` deep `#0E0D0B` ink `#F2EFE9` ink2 `#C6C1B7` ink3 `#B0AA9E` muted `#8C877E` line `#34322D` strong `#48453F` accent `#FF6A5C` live `#4ADFC4`; syn `#FF7B71 #E8B45B #43D1B4 #7FA9F5 #BB97F0 #8C877E`

### Settings / defaults changes

- `galley.theme` (String id, default "thesis"); `galley.mode` ("system" | "light" | "dark",
  default "system") **replaces** `galley.appearance` (migrate: paper→light, ink→dark,
  system→system, one-shot in `registerGalleyDefaults`/first read).
- **Remove** the global `galley.typeface` setting, its `Typeface` enum usage in
  pickers, and the View ▸ Typeface menu (fonts are now per-theme; keep reading the
  old key only for migration silence). Keep `textScale`, `measure`.
- `Appearance` enum → rename usage to mode; keep `system/paper/ink` raw-value
  compatibility out of persisted state.

### Wire-through (Swift → JS)

`ReaderModel.pushOptions()` builds:

```json
{ "mode": "light"|"dark",            // resolved (system → NSApp appearance)
  "palette": { every ThemePalette field, resolved with overrides },
  "fonts": { "display": css, "body": css, "mono": css },
  "headingWeight": 600,
  "spectral": true,
  "measure": 70, "scale": 1.0, "presenting": false, "allowRemote": true }
```

`underPageBackgroundColor` = palette.bg. Window appearance follows resolved mode
(NSApp.appearance, as today). Mermaid re-render on palette change (JS already
re-themes on appearance flip — key it on palette.bg change instead).

### JS/CSS (`web/src/render.js`, `Galley/Resources/web/theme.css`)

- `applyOptions` sets CSS custom properties from the payload:
  `--bg --bg-hi --bg-deep --ink --ink-2 --ink-3 --muted --line --line-strong
   --accent --live --syn-* --font-display --font-body --font-mono
   --heading-weight`, plus `data-mode` (light|dark) and `data-spectral` ("true"/"false")
  on `:root`. Remove the old `data-appearance`/`data-typeface` blocks from
  theme.css — the :root defaults stay (thesis light) so the page never flashes
  unstyled, but variants come from JS-set vars now.
- Headings use `font-weight: var(--heading-weight)`; h1 keeps its relative bump.
- `data-spectral="false"`: h1::after → `var(--accent)`; `hr` → hairline
  (`var(--line-strong)`, no gradient); link hover underline → solid `var(--accent)`;
  callout/live-dot/fm styling unchanged. Keep `--spectral` gradient var for
  spectral themes only.
- Code block bg on dark uses `--bg-deep` (as today).
- Mermaid themeVariables: read the new vars (already does via computed style).

### UI

- **AppearancePopover (Aa)** redesign: theme picker (5 rows: name + 3-swatch chip:
  bg/ink/accent of current variant), mode segmented (System/Light/Dark), size
  slider, line-width segmented, "Spectral accents" toggle (binds to override).
  Width ~300.
- **Settings ▸ Appearance** full editor: theme picker; for the selected theme —
  display/body/mono font pickers (FontChoice), heading weight slider (500–800,
  step 20), spectral toggle, and two color groups ("Light" / "Dark"): Background,
  Text, Accent as `ColorPicker`s bound to hex overrides; "Reset This Theme"
  button clears its overrides. Use small swatch previews. Keep it calm.
- **View menu**: Theme submenu lists the 5 themes; Mode submenu
  System/Light/Dark. Remove Typeface submenu.

---

## Part B — Edit mode (explicit, honest, full-function source editing)

### Semantics

- Documents ALWAYS open in view mode. Edit is entered via toolbar pencil or
  **⌘⇧E** ("Edit Markdown" ↔ "Done Editing" in the menu).
- `canEdit`: fileURL != nil && `FileManager.default.isWritableFile(atPath:)` &&
  URL is not inside `Bundle.main.bundleURL` (Welcome/Tour are read-only —
  disable the button with a help tooltip).
- **Save is explicit**: ⌘S writes `draftText` atomically (`.atomic`) to fileURL,
  updates `markdown`, re-renders, stays in edit mode. The FileWatcher's
  rename-survival already tolerates the atomic save; the `text != markdown`
  guard makes the self-triggered event a no-op.
- Exiting edit mode with unsaved changes → NSAlert: **Save** / **Discard
  Changes** / **Cancel**.
- Closing the window with unsaved changes must NOT lose them: when entering
  edit mode, install a `WindowCloseGuard` (NSObject) as `window.delegate`,
  keeping the original delegate and forwarding everything via
  `forwardingTarget(for:)` + `responds(to:)`; implement `windowShouldClose` →
  if dirty, show the same Save/Discard/Cancel alert (Save then close). Restore
  the original delegate when leaving edit mode.
- External change while editing: watcher fires && isEditing && isDirty → do NOT
  re-render; show a banner "This file changed on disk." [Use Disk Version]
  [Keep Mine]. If not dirty, silently refresh `draftText` + `markdown`.
- Live reload / follow-tail continue to work in view mode exactly as today.

### Editor (`Galley/Views/MarkdownEditorView.swift`, new)

NSViewRepresentable wrapping NSScrollView + NSTextView:

- Plain text (`isRichText false`), `allowsUndo true`, `usesFindBar true`,
  continuous spell checking ON, and ALL of: automatic quote substitution, dash
  substitution, text replacement, spelling correction OFF (it's Markdown).
- Typography from the current theme: mono font (theme monoFont, ~13.5pt ×
  textScale), palette bg/ink, accent insertion point + selection tint,
  `textContainerInset ≈ (28, 32)`, line height multiple ~1.5 via paragraph style.
- **Source highlighting** (`Galley/Core/MarkdownSourceHighlighter.swift`, new):
  regex-based temporary attributes over the whole string (documents < 300 KB;
  above that, skip highlighting): headings (accent, bold), `**bold**`/`*italic*`
  (ink weight/italic), inline code + fenced blocks (bgHi background, synTeal
  tint for fence info), links `[t](u)` (accent for the URL part, underline
  none), blockquote `>` lines (muted), list markers (accent), front-matter
  block (muted). Debounce re-highlight ~150 ms after edits; highlight only the
  edited paragraph range plus fences when feasible — keep it simple and
  correct first (full-doc pass is fine under 300 KB).
- Bind text to `model.draftText` (Coordinator textDidChange → model; model →
  textView only when strings differ, preserving selection).
- ⌘F in edit mode goes to the text view's find bar: the Find… command checks
  `model.isEditing` and calls `performTextFinderAction(.showFindInterface)` on
  the first responder / stored weak textView reference instead of the web find.

### ReaderModel additions

`@Published isEditing`, `@Published draftText`, `@Published isDirty`,
`@Published externalChangePending`, `canEdit`, `enterEdit()`, `saveDraft()`,
`requestExitEdit()` (alert flow), `adoptDiskVersion()`, `keepMineDismissDisk()`.
While `isEditing`, `pushContent` calls are suppressed (view is hidden anyway);
on exit, re-render from current `markdown`.

### DocumentView

- ZStack: reader stack (unchanged) + editor; swap with `opacity`/`allowsHitTesting`
  so the WKWebView stays alive and view state survives round-trips.
- Toolbar: pencil `square.and.pencil` toggle (filled/accented while editing,
  help "Edit Markdown (⌘⇧E)"), disabled when !canEdit; while editing show a
  **Save** button (disabled when !dirty) and hide Info popover + live dot; keep
  Aa (themes apply to the editor too — coordinator observes options pushes and
  re-fonts). Window `isDocumentEdited` mirrors `isDirty` (dot in the close button).
- Subtitle shows "Editing" while in edit mode (append to badge).
- External-change banner (edit mode variant) alongside existing banners.

### Commands

- File group: **Save** (⌘S, enabled only when editing && dirty), above the
  export items.
- Edit group: **Edit Markdown / Done Editing** ⌘⇧E (toggles, disabled when
  !canEdit).
- Find… routes per mode (web find bar vs text finder) as above.

---

## Part C — polish and repairs

1. **Toolbar live-dot spacing bug** (user screenshot): the 7 px LiveDot circle
   sits in the grouped toolbar pill with no breathing room. Give it its own
   ToolbarItem before the group with `.frame(width: 18, height: 18)` and
   horizontal padding 4; hidden while editing.
2. Docs: README (edit mode section, themes section, updated shortcut table:
   ⌘⇧E Edit, ⌘S Save), Welcome.md ("Need to fix a typo? ⌘⇧E is a deliberate
   edit mode — Galley still never opens into an editor."), DESIGN.md addendum
   (v1.1: themes + edit mode, moat rationale), appstore metadata bullets.
3. Migration note in DISTRIBUTION.md is not needed (defaults migrate silently).

## Build discipline (every phase)

```bash
cd /Users/jessiesalas/Projects/galley
xcodegen generate                       # after adding files
cd web && npx esbuild src/render.js --bundle --minify --format=iife --outfile=../Galley/Resources/web/reader.bundle.js && cd ..
xcodebuild -project Galley.xcodeproj -scheme Galley -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY="-" build
```

Iterate until BUILD SUCCEEDED with zero errors. Do not commit; the orchestrator
reviews, tests the running app, and commits.
