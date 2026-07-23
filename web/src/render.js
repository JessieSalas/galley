/*
 * Reader render pipeline.
 * Bundled with esbuild into reader.bundle.js — no runtime dependencies.
 * Native app drives this via the global `Reader` object; messages flow
 * back through webkit.messageHandlers.reader (absent in the dev harness).
 */

import MarkdownIt from "markdown-it";
import footnote from "markdown-it-footnote";
import anchor from "markdown-it-anchor";
import taskLists from "markdown-it-task-lists";
import hljs from "highlight.js/lib/common";
import * as yaml from "js-yaml";

// A few extra languages beyond the "common" set that show up constantly
// in AI-era markdown.
import swift from "highlight.js/lib/languages/swift";
import dockerfile from "highlight.js/lib/languages/dockerfile";
import nginx from "highlight.js/lib/languages/nginx";
hljs.registerLanguage("swift", swift);
hljs.registerLanguage("dockerfile", dockerfile);
hljs.registerLanguage("nginx", nginx);

const CALLOUT_KINDS = ["note", "tip", "important", "warning", "caution"];

const state = {
  docDir: null, // absolute dir of the open file, for relative asset resolution
  options: {
    appearance: "paper", // paper | ink
    typeface: "default", // default | serif | mono | system
    measure: 70, // ch
    scale: 1.0,
    leading: 1.68,
    allowRemote: true,
    presenting: false,
  },
  raw: "",
  showFrontMatter: true,
  typographer: true,
  lastLoadArgs: null,
  mermaidLoaded: false,
  katexLoaded: false,
  lastRenderSeq: 0,
};

/* ---------------- markdown-it setup ---------------- */

function highlight(code, lang) {
  if (lang && hljs.getLanguage(lang)) {
    try {
      return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    } catch (_) {}
  }
  return escapeHtml(code);
}

function escapeHtml(s) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function makeMD(typographer) {
  const instance = new MarkdownIt({
    html: true,
    linkify: true,
    typographer,
    highlight,
  })
    .use(footnote)
    .use(taskLists, { enabled: false, label: true })
    .use(anchor, {
      slugify: slugify,
      tabIndex: false,
    });
  instance.linkify.set({ fuzzyLink: false });
  installRules(instance);
  return instance;
}

let md; // created below, after the custom renderer rules are defined

function slugify(s) {
  return String(s)
    .trim()
    .toLowerCase()
    .replace(/[ -⁯⸀-⹿'!"#$%&()*+,./:;<=>?@[\]^`{|}~]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/* fenced code: wrap in .codeblock with language label + copy button;
   mermaid fences become placeholders rendered lazily after layout. */
function installRules(instance) {
  instance.renderer.rules.fence = (tokens, idx, opts, env, self) => {
    const token = tokens[idx];
    const info = (token.info || "").trim();
    const lang = info.split(/\s+/)[0].toLowerCase();

    if (lang === "mermaid") {
      return `<div class="mermaid-block" data-mermaid="${escapeHtml(
        encodeURIComponent(token.content)
      )}"><div class="mermaid-pending"></div></div>\n`;
    }
    if (lang === "math" || lang === "katex" || lang === "latex") {
      return `<div class="math-block" data-math="${escapeHtml(
        encodeURIComponent(token.content)
      )}"></div>\n`;
    }

    const body = highlight(token.content, lang);
    const langLabel = lang
      ? `<span class="code-lang">${escapeHtml(lang)}</span>`
      : "";
    return (
      `<div class="codeblock">` +
      `<div class="code-toolbar">${langLabel}<button class="code-copy" type="button">copy</button></div>` +
      `<pre><code class="hljs">${body}</code></pre>` +
      `</div>\n`
    );
  };

  /* images/media: route relative paths through the native asset scheme.
     Mirrors markdown-it's default image rule (alt from inline children). */
  instance.renderer.rules.image = (tokens, idx, opts, env, self) => {
    const token = tokens[idx];
    const srcIdx = token.attrIndex("src");
    if (srcIdx >= 0) {
      token.attrs[srcIdx][1] = resolveAssetURL(token.attrs[srcIdx][1]);
    }
    token.attrSet("alt", self.renderInlineAsText(token.children || [], opts, env));
    return self.renderToken(tokens, idx, opts);
  };
}

md = makeMD(true);

function resolveAssetURL(src) {
  if (!src) return src;
  if (/^(https?|data|blob):/i.test(src)) {
    return state.options.allowRemote ? src : "";
  }
  if (/^doc-asset:/i.test(src)) return src;
  if (!state.docDir) return src;
  // resolve relative to the document directory through the native scheme
  let path = src;
  if (!path.startsWith("/")) {
    path = state.docDir.replace(/\/$/, "") + "/" + path;
  }
  // normalize ../ and ./ segments
  const parts = [];
  for (const seg of path.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") parts.pop();
    else parts.push(seg);
  }
  return "doc-asset:///" + parts.map(encodeURIComponent).join("/");
}

/* ---------------- front matter ---------------- */

function splitFrontMatter(text) {
  // tolerate a BOM and CRLF line endings (Windows-authored files)
  const m = /^﻿?---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*\r?(\n|$)/.exec(text);
  if (!m) return { fm: null, body: text };
  try {
    const fm = yaml.load(m[1], { schema: yaml.JSON_SCHEMA });
    if (fm && typeof fm === "object" && !Array.isArray(fm)) {
      return { fm, body: text.slice(m[0].length) };
    }
  } catch (_) {}
  return { fm: null, body: text };
}

function renderFrontMatter(fm) {
  const host = document.getElementById("fm");
  host.innerHTML = "";
  if (!fm) return;
  const entries = Object.entries(fm).filter(([, v]) => v !== null && v !== "");
  if (!entries.length) return;

  const card = document.createElement("div");
  card.className = "fm-card";
  const label = document.createElement("div");
  label.className = "fm-label";
  label.textContent = "document";
  card.appendChild(label);

  for (const [key, value] of entries.slice(0, 12)) {
    const row = document.createElement("div");
    row.className = "fm-row";
    const k = document.createElement("div");
    k.className = "fm-key";
    k.textContent = key;
    const v = document.createElement("div");
    v.className = "fm-val";
    if (Array.isArray(value)) {
      for (const item of value.slice(0, 8)) {
        const tag = document.createElement("span");
        tag.className = "fm-tag";
        tag.textContent = String(item);
        v.appendChild(tag);
      }
    } else if (typeof value === "object") {
      v.textContent = JSON.stringify(value);
    } else {
      v.textContent = String(value);
    }
    row.appendChild(k);
    row.appendChild(v);
    card.appendChild(row);
  }
  host.appendChild(card);
}

/* ---------------- remote content policy ----------------
   Markdown can carry raw HTML; when remote images are disabled, strip
   any http(s) media source the parser didn't already catch. iframes and
   friends never load remote pages (the native navigation policy blocks
   them), but remove them anyway so no placeholder chrome shows. */

function sanitizeRemote(root) {
  for (const el of root.querySelectorAll("iframe, object, embed")) el.remove();
  if (state.options.allowRemote) return;
  for (const el of root.querySelectorAll("img[src], video[src], audio[src], source[src]")) {
    if (/^https?:/i.test(el.getAttribute("src") || "")) el.removeAttribute("src");
  }
  for (const el of root.querySelectorAll("[srcset]")) el.removeAttribute("srcset");
}

/* Raw HTML in markdown is allowed for layout (tables, <details>, <img>), but
   never for behavior: strip scripts, on*-handlers, and javascript: URLs.
   The template's CSP is the second lock on the same door. */
function sanitizeDOM(root) {
  for (const el of root.querySelectorAll("script, noscript")) el.remove();
  for (const el of root.querySelectorAll("*")) {
    for (const attr of Array.from(el.attributes)) {
      const name = attr.name.toLowerCase();
      if (name.startsWith("on") || name === "srcdoc") {
        el.removeAttribute(attr.name);
      } else if (
        (name === "href" || name === "src" || name === "xlink:href" || name === "action" || name === "formaction") &&
        /^\s*javascript:/i.test(attr.value)
      ) {
        el.removeAttribute(attr.name);
      }
    }
  }
}

/* ---------------- GitHub-style alerts ---------------- */

function transformCallouts(root) {
  for (const bq of root.querySelectorAll("blockquote")) {
    const first = bq.querySelector("p");
    if (!first) continue;
    const m = /^\[!(\w+)\]\s*/.exec(first.textContent || "");
    if (!m) continue;
    const kind = m[1].toLowerCase();
    if (!CALLOUT_KINDS.includes(kind)) continue;

    const div = document.createElement("div");
    div.className = "callout";
    div.dataset.kind = kind;
    const title = document.createElement("div");
    title.className = "callout-title";
    title.textContent = kind;
    div.appendChild(title);

    // strip the [!kind] marker from the first paragraph
    const walker = document.createTreeWalker(first, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    if (node) node.textContent = node.textContent.replace(/^\[!\w+\]\s*/, "");
    while (bq.firstChild) div.appendChild(bq.firstChild);
    // drop an empty leading paragraph if the marker was alone
    const lead = div.querySelector(".callout-title + p");
    if (lead && !lead.textContent.trim() && !lead.querySelector("img")) lead.remove();
    bq.replaceWith(div);
  }
}

/* ---------------- lazy heavyweights: mermaid + katex ---------------- */

function loadScript(src) {
  return new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = src;
    s.onload = resolve;
    s.onerror = reject;
    document.head.appendChild(s);
  });
}

function loadStylesheet(href) {
  return new Promise((resolve, reject) => {
    const l = document.createElement("link");
    l.rel = "stylesheet";
    l.href = href;
    l.onload = resolve;
    l.onerror = reject;
    document.head.appendChild(l);
  });
}

function mermaidThemeVariables() {
  const css = getComputedStyle(document.documentElement);
  const v = (name) => css.getPropertyValue(name).trim();
  const dark = document.documentElement.dataset.appearance === "ink";
  return {
    fontFamily: v("--font-body") || "Inter, sans-serif",
    fontSize: "14.5px",
    primaryColor: dark ? "#1e1d14" : "#f8f5ee",
    primaryTextColor: v("--ink"),
    primaryBorderColor: v("--line-strong"),
    lineColor: v("--ink-2"),
    secondaryColor: dark ? "#26241a" : "#eae4d6",
    tertiaryColor: dark ? "#17160f" : "#f1ece2",
    background: dark ? "#1e1d14" : "#f8f5ee",
    mainBkg: dark ? "#26241a" : "#f8f5ee",
    nodeBorder: v("--line-strong"),
    clusterBkg: dark ? "#17160f" : "#f1ece2",
    titleColor: v("--ink"),
    edgeLabelBackground: dark ? "#1e1d14" : "#f8f5ee",
    actorBorder: v("--line-strong"),
    actorBkg: dark ? "#26241a" : "#f8f5ee",
    noteBkgColor: dark ? "#332f1e" : "#f6ecd4",
    noteBorderColor: v("--line-strong"),
    pie1: "#ff5d73", pie2: "#ffb454", pie3: "#36d6c3",
    pie4: "#6aa6ff", pie5: "#b07bff", pie6: "#c3bcac",
  };
}

let mermaidRenderSeq = 0;

async function renderMermaidBlocks(root) {
  const blocks = root.querySelectorAll(".mermaid-block[data-mermaid]");
  if (!blocks.length) return;

  if (!state.mermaidLoaded) {
    await loadScript("vendor/mermaid.min.js");
    state.mermaidLoaded = true;
  }
  window.mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    themeVariables: mermaidThemeVariables(),
  });

  for (const block of blocks) {
    const src = decodeURIComponent(block.dataset.mermaid);
    const id = `mmd-${++mermaidRenderSeq}`;
    try {
      const { svg } = await window.mermaid.render(id, src);
      block.innerHTML = svg;
    } catch (err) {
      // mermaid.render leaves a dangling error element; remove it
      document.getElementById("d" + id)?.remove();
      block.classList.add("mermaid-error");
      block.innerHTML =
        `<div class="mermaid-error-note">diagram could not be rendered</div>` +
        `<pre><code>${escapeHtml(src)}</code></pre>`;
    }
  }
}

async function renderMath(root) {
  // A document is "mathy" only if it uses display math or TeX commands —
  // this keeps "$5 and $10" prose from turning into accidental equations.
  const mathy = /\$\$|\\\(|\\\[|\\begin\{/.test(state.raw);
  const hasDollar = mathy && /\$[^\s$]/.test(state.raw);
  const mathBlocks = root.querySelectorAll(".math-block[data-math]");
  if (!mathy && !mathBlocks.length) return;

  if (!state.katexLoaded) {
    await loadStylesheet("vendor/katex/katex.min.css");
    await loadScript("vendor/katex/katex.min.js");
    await loadScript("vendor/katex/auto-render.min.js");
    state.katexLoaded = true;
  }

  for (const el of mathBlocks) {
    const src = decodeURIComponent(el.dataset.math);
    try {
      window.katex.render(src, el, { displayMode: true, throwOnError: false });
    } catch (_) {
      el.textContent = src;
    }
  }

  if (mathy && window.renderMathInElement) {
    const delimiters = [
      { left: "$$", right: "$$", display: true },
      { left: "\\[", right: "\\]", display: true },
      { left: "\\(", right: "\\)", display: false },
    ];
    if (hasDollar) delimiters.push({ left: "$", right: "$", display: false });
    window.renderMathInElement(root, {
      delimiters,
      throwOnError: false,
      ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code", "option"],
    });
  }
}

/* ---------------- toc + stats ---------------- */

function collectTOC(root) {
  const toc = [];
  for (const h of root.querySelectorAll("h1, h2, h3, h4")) {
    const clone = h.cloneNode(true);
    for (const btn of clone.querySelectorAll(".anchor-btn")) btn.remove();
    toc.push({
      level: Number(h.tagName[1]),
      text: clone.textContent.trim(),
      id: h.id || "",
    });
  }
  return toc;
}

function computeStats(bodyText) {
  const text = bodyText.trim();
  const words = text ? (text.match(/\S+/g) || []).length : 0;
  const chars = text.length;
  const minutes = Math.max(1, Math.round(words / 225));
  const tokens = Math.round(chars / 4);
  return { words, chars, minutes, tokens };
}

/* ---------------- interactivity ---------------- */

function wireContent(root) {
  // copy buttons
  for (const btn of root.querySelectorAll(".code-copy")) {
    btn.addEventListener("click", () => {
      const code = btn.closest(".codeblock")?.querySelector("pre code");
      if (!code) return;
      navigator.clipboard.writeText(code.textContent).then(() => {
        btn.textContent = "copied";
        btn.classList.add("copied");
        setTimeout(() => {
          btn.textContent = "copy";
          btn.classList.remove("copied");
        }, 1400);
      });
    });
  }

  // heading anchor buttons
  for (const h of root.querySelectorAll("h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]")) {
    const btn = document.createElement("button");
    btn.className = "anchor-btn";
    btn.type = "button";
    btn.title = "Copy link to section";
    btn.textContent = "¶";
    btn.addEventListener("click", () => {
      post("anchorCopy", { id: h.id });
      navigator.clipboard.writeText("#" + h.id);
    });
    h.appendChild(btn);
  }

  // broken local images get a quiet marker so native can offer folder access
  for (const img of root.querySelectorAll("img")) {
    img.addEventListener("error", () => {
      img.classList.add("img-broken");
      if (img.src.startsWith("doc-asset:")) post("assetMissing", { src: img.src });
    }, { once: true });
  }
}

/* single delegated click handler for links */
document.addEventListener("click", (e) => {
  const a = e.target.closest("a");
  if (!a) return;
  const href = a.getAttribute("href") || "";
  if (!href) return;

  if (href.startsWith("#")) {
    e.preventDefault();
    const el = document.getElementById(decodeURIComponent(href.slice(1)));
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    return;
  }
  e.preventDefault();
  post("link", { href });
  if (!window.webkit?.messageHandlers?.reader) {
    // dev harness: open externally
    window.open(href, "_blank");
  }
});

/* keyboard: space/shift-space page, cmd handled natively */
document.addEventListener("keydown", (e) => {
  if (e.key === " " && !e.metaKey && !e.ctrlKey && !e.altKey) {
    e.preventDefault();
    window.scrollBy({
      top: (e.shiftKey ? -1 : 1) * window.innerHeight * 0.85,
      behavior: "smooth",
    });
  }
});

/* the reader's own scrolling wins over post-render position pinning */
let userScrolledSinceRender = false;
window.addEventListener("wheel", () => { userScrolledSinceRender = true; }, { passive: true });
window.addEventListener("touchmove", () => { userScrolledSinceRender = true; }, { passive: true });
window.addEventListener("keydown", (e) => {
  if (["ArrowDown", "ArrowUp", "PageDown", "PageUp", "Home", "End", " "].includes(e.key)) {
    userScrolledSinceRender = true;
  }
});

/* scroll reporting (throttled) */
let scrollTimer = null;
window.addEventListener("scroll", () => {
  if (scrollTimer) return;
  scrollTimer = setTimeout(() => {
    scrollTimer = null;
    post("scroll", { fraction: getScrollFraction(), activeHeading: activeHeadingId() });
  }, 120);
}, { passive: true });

function getScrollFraction() {
  const h = document.documentElement;
  const max = h.scrollHeight - h.clientHeight;
  return max > 0 ? h.scrollTop / max : 0;
}

function setScrollFraction(f) {
  // Called by the native side to restore a saved reading position — it
  // outranks the render pipeline's own position pinning.
  userScrolledSinceRender = true;
  const h = document.documentElement;
  h.scrollTop = f * (h.scrollHeight - h.clientHeight);
}

function activeHeadingId() {
  const headings = document.querySelectorAll(".doc h1[id], .doc h2[id], .doc h3[id], .doc h4[id]");
  let current = "";
  for (const h of headings) {
    if (h.getBoundingClientRect().top <= 90) current = h.id;
    else break;
  }
  return current;
}

function isNearBottom() {
  const h = document.documentElement;
  return h.scrollHeight - h.clientHeight - h.scrollTop < 120;
}

/* ---------------- native bridge ---------------- */

function post(type, payload = {}) {
  try {
    window.webkit?.messageHandlers?.reader?.postMessage({ type, ...payload });
  } catch (_) {}
}

/* ---------------- public API ---------------- */

const Reader = {
  /** Full (re)render. opts: { markdown, docDir, isReload, followTail,
      showFrontMatter, typographer } */
  async load({
    markdown,
    docDir = null,
    isReload = false,
    followTail = false,
    showFrontMatter = true,
    typographer = true,
  }) {
    const seq = ++state.lastRenderSeq;
    state.docDir = docDir;
    state.raw = markdown;
    state.showFrontMatter = showFrontMatter;
    state.lastLoadArgs = { markdown, docDir, showFrontMatter, typographer };
    if (typographer !== state.typographer) {
      state.typographer = typographer;
      md = makeMD(typographer);
    }

    const prevScroll = document.documentElement.scrollTop;
    const wasAtBottom = isNearBottom();

    const { fm, body } = splitFrontMatter(markdown);
    const content = document.getElementById("content");

    renderFrontMatter(showFrontMatter ? fm : null);
    content.innerHTML = md.render(body);
    if (seq !== state.lastRenderSeq) return; // superseded

    sanitizeDOM(content);
    transformCallouts(content);
    sanitizeRemote(content);
    wireContent(content);

    // Scroll target for this render; re-applied as async decorations
    // (math, diagrams, image decode) change the document height —
    // unless the reader has scrolled in the meantime.
    const target =
      isReload && followTail && wasAtBottom
        ? { mode: "bottom" }
        : isReload
          ? { mode: "keep", y: prevScroll }
          : { mode: "top" };
    userScrolledSinceRender = false;

    const applyTarget = () => {
      if (userScrolledSinceRender) return;
      const h = document.documentElement;
      if (target.mode === "bottom") h.scrollTop = h.scrollHeight;
      else if (target.mode === "keep") h.scrollTop = target.y;
      else h.scrollTop = 0;
    };
    applyTarget();

    post("toc", { items: collectTOC(content) });
    post("stats", { ...computeStats(content.innerText), frontMatter: fm ? Object.keys(fm) : [] });

    await renderMath(content);
    if (seq !== state.lastRenderSeq) return;
    await renderMermaidBlocks(content);
    if (seq !== state.lastRenderSeq) return;
    applyTarget();

    if (isReload) showLivePill();
    post("rendered", { isReload });

    // Late image decodes still shift layout; settle once, then pin again.
    await Promise.allSettled(
      Array.from(content.querySelectorAll("img")).map((img) =>
        img.decode ? img.decode().catch(() => {}) : Promise.resolve()
      )
    );
    if (seq !== state.lastRenderSeq) return;
    applyTarget();
  },

  applyOptions(opts) {
    const prevAppearance = state.options.appearance;
    const prevRemote = state.options.allowRemote;
    Object.assign(state.options, opts);
    const rootEl = document.documentElement;
    rootEl.dataset.appearance = state.options.appearance;
    rootEl.dataset.typeface = state.options.typeface;
    rootEl.dataset.presenting = String(!!state.options.presenting);
    rootEl.style.setProperty("--measure", state.options.measure + "ch");
    rootEl.style.setProperty("--scale", String(state.options.scale));
    rootEl.style.setProperty("--leading", String(state.options.leading));

    // re-theme mermaid diagrams on appearance change
    if (
      prevAppearance !== state.options.appearance &&
      state.mermaidLoaded &&
      document.querySelector(".mermaid-block")
    ) {
      renderMermaidFromRaw();
    }
    // remote-image policy flipped → re-render from source
    if (prevRemote !== state.options.allowRemote && state.lastLoadArgs) {
      Reader.load({ ...state.lastLoadArgs, isReload: true, followTail: false });
    }
  },

  scrollToAnchor(id) {
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  },

  scrollToTop() { window.scrollTo({ top: 0, behavior: "smooth" }); },
  scrollToBottom() {
    window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "smooth" });
  },
  setScrollFraction,
  getScrollFraction,

  getRawMarkdown() { return state.raw; },

  /** Self-contained HTML export of the current document. */
  exportHTML() {
    const clone = document.documentElement.cloneNode(true);
    for (const el of clone.querySelectorAll("script, #live-pill, .code-toolbar, .anchor-btn")) el.remove();
    return "<!doctype html>\n" + clone.outerHTML;
  },
};

async function renderMermaidFromRaw() {
  // re-render mermaid blocks from their embedded source with the current theme
  const content = document.getElementById("content");
  for (const block of content.querySelectorAll(".mermaid-block")) {
    if (!block.dataset.mermaid) continue;
    block.classList.remove("mermaid-error");
    block.innerHTML = `<div class="mermaid-pending"></div>`;
  }
  await renderMermaidBlocks(content);
}

let pillTimer = null;
function showLivePill() {
  const pill = document.getElementById("live-pill");
  if (!pill) return;
  pill.classList.add("show");
  clearTimeout(pillTimer);
  pillTimer = setTimeout(() => pill.classList.remove("show"), 1800);
}

window.Reader = Reader;
post("ready", {});
