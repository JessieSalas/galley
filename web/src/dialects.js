/* Normalizes the Markdown dialects people actually have on disk into the
   subset markdown-it understands, so a Notion or Obsidian export reads as a
   document instead of as someone else's syntax leaking through.

   Shared deliberately by the app renderer and the Quick Look preview, so a
   file can't look right in one and wrong in the other. (The Finder thumbnail
   is separate — pure AppKit, no JavaScript — and has its own text handling.)
   Quick Look renders with html:false, which is why the Notion rewrite below
   produces Markdown rather than relying on raw HTML.

   Everything here is conservative. A construct is only rewritten when the
   syntax is unambiguous; anything unrecognized is left exactly as written,
   because silently mangling someone's text is worse than not styling it. */

// Sourced from markdown-it-emoji rather than hand-maintained: ~1900 names,
// and the point is to match what GitHub/Slack/Discord users already type.
import EMOJI from "markdown-it-emoji/lib/data/full.mjs";

/* ---------------- Notion callouts ---------------- */

/* Notion exports callouts as <aside>…</aside>, usually with a leading emoji
   as the icon. QuickLook escapes raw HTML (so you see the literal tags) and
   the app passed it through unstyled (so you see a stray emoji over a bare
   list). Both become a real callout by rewriting to a fenced marker the
   renderer styles. Content is re-indented into a blockquote so nested lists
   and paragraphs survive. */
const ASIDE_BLOCK = /^[ \t]*<aside>[ \t]*\n([\s\S]*?)\n?[ \t]*<\/aside>[ \t]*$/gm;

// A leading emoji on its own line (or starting the first line) is Notion's
// callout icon, not content.
const LEADING_EMOJI =
  /^[\s]*([‼-㊙\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}][\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}]*)[ \t]*/u;

export function normalizeNotionAsides(text) {
  return text.replace(ASIDE_BLOCK, (_match, inner) => {
    let body = inner.replace(/^\n+|\n+$/g, "");
    let icon = "";
    const m = LEADING_EMOJI.exec(body);
    if (m) {
      icon = m[1];
      body = body.slice(m[0].length).replace(/^\n+/, "");
    }
    if (!body.trim()) {
      // An empty aside is a Notion placeholder; dropping it beats rendering
      // an empty box.
      return "";
    }
    const quoted = body
      .split("\n")
      .map((line) => (line.trim() ? `> ${line}` : ">"))
      .join("\n");
    return `> [!callout${icon ? ` ${icon}` : ""}]\n${quoted}`;
  });
}

/* ---------------- emoji shortcodes ---------------- */

/* :smile: and friends show up in anything exported from GitHub, Slack,
   Discord or Notion. Known names become the real character; unknown ones
   (a team's custom :pixelpencil:, which is an image on someone else's
   server) are left alone rather than guessed at or deleted. */
const SHORTCODE = /:([a-z0-9_+-]{1,40}):/gi;

export function normalizeEmojiShortcodes(text) {
  return text.replace(SHORTCODE, (match, name) => {
    const hit = EMOJI[name.toLowerCase()];
    return hit || match;
  });
}

/* ---------------- Obsidian ---------------- */

/* ==highlight== is Obsidian's, and is also common in Notion exports. */
export function normalizeHighlights(text) {
  return text.replace(/==(?!\s)([^\n=]+?)(?<!\s)==/g, "<mark>$1</mark>");
}

/* [[Wiki Links]] and [[target|label]]. There is no vault to resolve against,
   so these render as plain emphasized text rather than dead links that look
   clickable and go nowhere. */
export function normalizeWikiLinks(text) {
  return text.replace(/\[\[([^\]\n|]+)(?:\|([^\]\n]+))?\]\]/g, (_m, target, label) => {
    const shown = (label || target).trim();
    return `*${shown}*`;
  });
}

/* ---------------- entry point ---------------- */

/* Order matters: asides first (they wrap other constructs), then inline
   rewrites. Fenced code is protected by splitting on fences and only
   transforming the prose between them, so a document *about* this syntax
   still shows it verbatim. */
const FENCE = /^(?:[ \t]*)(?:```|~~~)[^\n]*$/gm;

export function normalizeDialects(text) {
  if (typeof text !== "string" || !text) return text;

  const lines = text.split("\n");
  const out = [];
  let inFence = false;
  let fenceMarker = "";
  let buffer = [];

  const flush = () => {
    if (!buffer.length) return;
    let chunk = buffer.join("\n");
    chunk = normalizeNotionAsides(chunk);
    chunk = normalizeEmojiShortcodes(chunk);
    chunk = normalizeHighlights(chunk);
    chunk = normalizeWikiLinks(chunk);
    out.push(chunk);
    buffer = [];
  };

  for (const line of lines) {
    const fence = /^[ \t]*(```+|~~~+)/.exec(line);
    if (!inFence && fence) {
      flush();
      inFence = true;
      fenceMarker = fence[1][0];
      out.push(line);
      continue;
    }
    if (inFence) {
      out.push(line);
      const closing = /^[ \t]*(```+|~~~+)[ \t]*$/.exec(line);
      if (closing && closing[1][0] === fenceMarker) inFence = false;
      continue;
    }
    buffer.push(line);
  }
  flush();
  return out.join("\n");
}

export { FENCE };

/* ---------------- callout rendering ---------------- */

/* GitHub alerts (`> [!note]`) and the Notion asides normalized above
   (`> [!callout 💡]`) become styled blocks.

   This is a markdown-it plugin rather than a DOM pass because Quick Look
   renders inside JavaScriptCore, where there is no DOM at all. Doing it on
   tokens is the only way the preview and the app can share one
   implementation instead of drifting apart. */
const ALERT_KINDS = ["note", "tip", "important", "warning", "caution"];
const MARKER = /^\[!(\w+)(?:[ \t]+([^\]\n]+))?\][ \t]*\n?/;

function escapeAttr(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function calloutPlugin(md) {
  md.core.ruler.push("galley_callouts", (state) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== "blockquote_open") continue;
      const para = tokens[i + 1];
      const inline = tokens[i + 2];
      if (!para || para.type !== "paragraph_open") continue;
      if (!inline || inline.type !== "inline") continue;

      const m = MARKER.exec(inline.content);
      if (!m) continue;
      const kind = m[1].toLowerCase();
      const icon = (m[2] || "").trim();
      if (kind !== "callout" && !ALERT_KINDS.includes(kind)) continue;

      // Find this blockquote's own close, not a nested one's.
      let depth = 0;
      let close = -1;
      for (let j = i; j < tokens.length; j++) {
        if (tokens[j].type === "blockquote_open") depth++;
        else if (tokens[j].type === "blockquote_close") {
          depth--;
          if (depth === 0) { close = j; break; }
        }
      }
      if (close === -1) continue;

      tokens[i].tag = "div";
      tokens[i].attrSet("class", "callout");
      tokens[i].attrSet("data-kind", kind);
      tokens[close].tag = "div";

      // Drop the marker from the visible text, on the inline token and its
      // first child, which is what actually gets rendered.
      inline.content = inline.content.replace(MARKER, "");
      const first = inline.children && inline.children[0];
      if (first && first.type === "text") {
        first.content = first.content.replace(MARKER, "");
      }
      // A marker alone on its line leaves an empty paragraph behind.
      if (!inline.content.trim() && (!inline.children || inline.children.every(
        (c) => c.type === "text" && !c.content.trim()
      ))) {
        tokens.splice(i + 1, 3);
      }

      // A Notion callout has an icon, not a severity. Labelling it "CALLOUT"
      // would put a word in the document its author never wrote.
      const label = kind === "callout"
        ? (icon ? `<div class="callout-icon">${escapeAttr(icon)}</div>` : "")
        : `<div class="callout-title">${escapeAttr(kind)}</div>`;
      if (label) {
        const badge = new state.Token("html_block", "", 0);
        badge.content = label;
        tokens.splice(i + 1, 0, badge);
      }
    }
    return true;
  });
}
