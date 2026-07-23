import QuickLookUI
import JavaScriptCore
import UniformTypeIdentifiers

/// Data-based Quick Look preview: markdown-it runs inside JavaScriptCore and
/// we hand Quick Look a static HTML page styled like the app. Deliberately
/// modest — no scripts, no diagrams, no remote loads. The app is the full
/// experience; this is the Space bar.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let markdown = Self.decode(data)
        let body = Self.renderHTML(markdown: markdown)
        let page = Self.wrap(body: body, title: request.fileURL.lastPathComponent)

        return QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 760, height: 900)
        ) { _ in
            page.data(using: .utf8) ?? Data()
        }
    }

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    static func renderHTML(markdown: String) -> String {
        guard let bundleURL = Bundle(for: PreviewProvider.self).url(forResource: "ql.bundle", withExtension: "js"),
              let script = try? String(contentsOf: bundleURL, encoding: .utf8),
              let context = JSContext()
        else {
            return "<pre>" + escape(markdown) + "</pre>"
        }
        context.evaluateScript(script)
        guard let fn = context.objectForKeyedSubscript("qlRender"),
              let result = fn.call(withArguments: [markdown])?.toString(),
              result != "undefined"
        else {
            return "<pre>" + escape(markdown) + "</pre>"
        }
        return result
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The app's reading theme, condensed for a static preview.
    static func wrap(body: String, title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>\(previewCSS)</style>
        </head>
        <body><div id="frame">\(body)</div></body>
        </html>
        """
    }

    static let previewCSS = """
    :root {
      --bg: #f1ece2; --bg-hi: #f8f5ee; --ink: #15140e; --ink-2: #4a4639;
      --muted: #8e8879; --line: #d9d3c6; --line-strong: #c3bcac;
      --spectral: linear-gradient(90deg,#ff5d73,#ffb454,#36d6c3,#6aa6ff,#b07bff);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #17160f; --bg-hi: #1e1d14; --ink: #ece7da; --ink-2: #c9c3b2;
        --muted: #8e8879; --line: #353327; --line-strong: #4a473a;
      }
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--ink);
      font: 15px/1.65 -apple-system, system-ui, sans-serif;
      -webkit-font-smoothing: antialiased; }
    #frame { max-width: 74ch; margin: 0 auto; padding: 2.2rem 2rem 4rem; }
    h1, h2, h3, h4, h5 { line-height: 1.15; letter-spacing: -0.02em; }
    h1 { font-size: 1.9em; margin: 0.2em 0 0.6em; }
    h1:first-child::after { content: ""; display: block; width: 3rem; height: 2px;
      margin-top: 0.6rem; background: var(--spectral); border-radius: 2px; }
    h2 { font-size: 1.4em; margin: 1.8em 0 0.5em; padding-top: 0.9em;
      border-top: 1px solid var(--line); }
    a { color: var(--ink); }
    blockquote { margin: 1.2em 0; padding-left: 1.1em;
      border-left: 2px solid var(--line-strong); color: var(--ink-2); }
    code { font: 0.86em ui-monospace, "SF Mono", monospace;
      background: var(--bg-hi); border: 1px solid var(--line);
      border-radius: 4px; padding: 0.08em 0.32em; }
    pre { background: var(--bg-hi); border: 1px solid var(--line);
      border-radius: 10px; padding: 0.9rem 1.1rem; overflow-x: auto; }
    pre code { background: none; border: 0; padding: 0; }
    table { border-collapse: collapse; width: 100%; font-size: 0.92em; }
    th { text-transform: uppercase; font-size: 0.72em; letter-spacing: 0.12em;
      color: var(--muted); text-align: left; }
    th, td { padding: 0.5rem 0.7rem; border-bottom: 1px solid var(--line); }
    img { max-width: 100%; border-radius: 8px; }
    img:not([src]), img[src=""] { display: none; }
    hr { border: 0; height: 1px; background: var(--spectral); opacity: 0.55; margin: 2em 0; }
    .fm-card { border: 1px solid var(--line); background: var(--bg-hi);
      border-radius: 12px; padding: 0.9rem 1.1rem; margin-bottom: 1.6rem; }
    .fm-label { font: 600 0.62em ui-monospace, monospace; letter-spacing: 0.22em;
      text-transform: uppercase; color: var(--muted); margin-bottom: 0.4rem; }
    .fm-row { display: flex; justify-content: space-between; gap: 1rem;
      padding: 0.3rem 0; border-bottom: 1px solid var(--line); font-size: 0.85em; }
    .fm-row:last-child { border-bottom: 0; }
    .fm-key { text-transform: uppercase; font: 0.78em ui-monospace, monospace;
      letter-spacing: 0.1em; color: var(--muted); }
    /* spectral-ish syntax accents */
    .hljs-comment, .hljs-quote { color: var(--muted); font-style: italic; }
    .hljs-keyword, .hljs-literal, .hljs-type { color: #7a51c7; }
    .hljs-string, .hljs-addition { color: #177a6e; }
    .hljs-number, .hljs-built_in, .hljs-meta { color: #9c6a1f; }
    .hljs-title, .hljs-section, .hljs-name { color: #3a6cc9; }
    .hljs-attr, .hljs-variable, .hljs-params { color: #c04a5e; }
    @media (prefers-color-scheme: dark) {
      .hljs-keyword, .hljs-literal, .hljs-type { color: #c9a2ff; }
      .hljs-string, .hljs-addition { color: #5de3d0; }
      .hljs-number, .hljs-built_in, .hljs-meta { color: #ffc37a; }
      .hljs-title, .hljs-section, .hljs-name { color: #8fbcff; }
      .hljs-attr, .hljs-variable, .hljs-params { color: #ff8a9a; }
    }
    """
}
