/* Tests for the dialect normalizer and callout plugin.
 *
 * These exist because a Notion export rendered as literal <aside> tags in
 * Quick Look and as an unstyled stray emoji in the app, and nothing caught
 * it. Run by scripts/release.sh; `node web/test.mjs` to run by hand.
 */
import assert from "node:assert/strict";
import MarkdownIt from "markdown-it";
import { normalizeDialects, calloutPlugin } from "./src/dialects.js";

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (err) {
    failures.push(`${name}\n    ${err.message.split("\n")[0]}`);
  }
}

// Both renderer configurations: the app allows raw HTML, Quick Look does not.
// A file must not render differently between them.
const app = new MarkdownIt({ html: true, linkify: true }).use(calloutPlugin);
const quicklook = new MarkdownIt({ html: false, linkify: true }).use(calloutPlugin);
const render = (md, src) => md.render(normalizeDialects(src));

const NOTION = `Use This Guide To…

<aside>
💡

- Understand how impact is measured
- Prepare for Talent Review

</aside>

Page Navigation`;

test("Notion aside becomes a callout in the app", () => {
  const out = render(app, NOTION);
  assert.match(out, /<div class="callout" data-kind="callout">/);
  assert.match(out, /<div class="callout-icon">💡<\/div>/);
  assert.doesNotMatch(out, /&lt;aside&gt;/);
  assert.doesNotMatch(out, /<aside>/);
});

test("Notion aside becomes a callout in Quick Look too", () => {
  const out = render(quicklook, NOTION);
  // The original bug: html:false escaped the tags into visible text.
  assert.doesNotMatch(out, /&lt;aside&gt;/);
  assert.match(out, /<div class="callout" data-kind="callout">/);
});

test("app and Quick Look agree byte for byte", () => {
  assert.equal(render(app, NOTION), render(quicklook, NOTION));
});

test("aside content survives, including list items", () => {
  const out = render(app, NOTION);
  assert.match(out, /Understand how impact is measured/);
  assert.match(out, /Prepare for Talent Review/);
});

test("an empty Notion aside renders nothing rather than an empty box", () => {
  const out = render(app, "Before\n\n<aside>\n\n</aside>\n\nAfter");
  assert.doesNotMatch(out, /callout/);
});

test("known emoji shortcodes resolve", () => {
  assert.match(render(app, "ship it :rocket:"), /🚀/);
});

test("unknown custom shortcodes are left exactly as written", () => {
  // :pixelpencil: is a custom Discord emoji: an image on someone else's
  // server, with no Unicode equivalent. Guessing or dropping it would both
  // be wrong.
  assert.match(render(app, "nice :pixelpencil: work"), /:pixelpencil:/);
});

test("GitHub alerts still work", () => {
  const out = render(app, "> [!warning]\n> Careful.");
  assert.match(out, /data-kind="warning"/);
  assert.match(out, /<div class="callout-title">warning<\/div>/);
  assert.match(out, /Careful\./);
});

test("an unknown alert kind is left as an ordinary quote", () => {
  const out = render(app, "> [!bogus]\n> text");
  assert.match(out, /<blockquote>/);
  assert.doesNotMatch(out, /class="callout"/);
});

test("fenced code is never rewritten", () => {
  const src = "```md\n<aside>\n:smile: ==no== [[link]]\n</aside>\n```";
  const out = render(app, src);
  assert.match(out, /&lt;aside&gt;/);
  assert.match(out, /:smile:/);
  assert.match(out, /==no==/);
  assert.match(out, /\[\[link\]\]/);
});

test("Obsidian highlights and wiki links normalize", () => {
  const out = render(app, "==hot== and [[Page|label]]");
  assert.match(out, /<mark>hot<\/mark>/);
    assert.match(out, /<em>label<\/em>/);
});

test("a document with none of this is untouched", () => {
  const plain = "# Title\n\nSome **text** and a [link](https://example.com).\n";
  assert.equal(normalizeDialects(plain), plain);
});

test("nested blockquotes don't swallow the wrong close tag", () => {
  const out = render(app, "> [!note]\n> outer\n>\n> > inner quote\n");
  assert.match(out, /data-kind="note"/);
  assert.match(out, /<blockquote>/); // the inner one survives as a quote
});

if (failures.length) {
  console.error(`\n${failures.length} failing:\n`);
  for (const f of failures) console.error("  ✗ " + f);
  process.exit(1);
}
console.log(`web: ${passed} tests passed`);
