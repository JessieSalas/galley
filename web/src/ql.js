/*
 * Quick Look bundle: runs inside JavaScriptCore (no DOM).
 * Exposes a single global `qlRender(markdown)` returning an HTML body string.
 * Kept deliberately light: no mermaid, no KaTeX, no client scripts —
 * Quick Look previews are static; the app is the full experience.
 */

import MarkdownIt from "markdown-it";
import footnote from "markdown-it-footnote";
import taskLists from "markdown-it-task-lists";
import hljs from "highlight.js/lib/common";

function escapeHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const md = new MarkdownIt({
  html: false, // no raw HTML in QL previews
  linkify: true,
  typographer: true,
  highlight(code, lang) {
    if (lang && hljs.getLanguage(lang)) {
      try {
        return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
      } catch (_) {}
    }
    return escapeHtml(code);
  },
})
  .use(footnote)
  .use(taskLists, { enabled: false, label: true });

md.linkify.set({ fuzzyLink: false });

function stripFrontMatter(text) {
  const m = /^﻿?---[ \t]*\n([\s\S]*?)\n---[ \t]*(\n|$)/.exec(text);
  if (!m) return { fmLines: null, body: text };
  return { fmLines: m[1], body: text.slice(m[0].length) };
}

globalThis.qlRender = function qlRender(markdown) {
  const { fmLines, body } = stripFrontMatter(markdown);
  let fmHTML = "";
  if (fmLines) {
    const rows = [];
    for (const line of fmLines.split("\n").slice(0, 12)) {
      const mm = /^(\w[\w -]*):\s*(.*)$/.exec(line.trim());
      if (mm && mm[2]) {
        rows.push(
          `<div class="fm-row"><div class="fm-key">${escapeHtml(mm[1])}</div>` +
            `<div class="fm-val">${escapeHtml(mm[2])}</div></div>`
        );
      }
    }
    if (rows.length) {
      fmHTML =
        `<div class="fm-card"><div class="fm-label">document</div>` +
        rows.join("") +
        `</div>`;
    }
  }
  return fmHTML + `<article class="doc">` + md.render(body) + `</article>`;
};
