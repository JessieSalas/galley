import AppKit
import WebKit
import UniformTypeIdentifiers

/// PDF, HTML, and print pipelines. All exports go through the user's save
/// panel (the sandbox grants write access to the chosen location).
@MainActor
enum Exporter {

    /// Paginated PDF through the print pipeline — same margins and pagination
    /// as ⌘P, silently saved to the chosen file.
    static func exportPDF(model: ReaderModel) {
        guard let webView = model.webView, let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName(model: model, ext: "pdf")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let info = makePrintInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            let operation = webView.printOperation(with: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = true
            // Explicit frame before running — macOS 26 (Tahoe) crash workaround.
            operation.view?.frame = webView.bounds
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    static func exportHTML(model: ReaderModel) {
        guard let webView = model.webView, let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedName(model: model, ext: "html")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            webView.evaluateJavaScript("Reader.exportHTML()") { result, _ in
                guard var html = result as? String else { return }
                html = inlineThemeCSS(into: html)
                html = inlineKatexCSS(into: html)
                html = inlineDocAssets(into: html)
                try? html.data(using: .utf8)?.write(to: url)
            }
        }
    }

    /// Paginated print. The explicit frame assignment before running works
    /// around a macOS 26 (Tahoe) crash in NSPrintOperation with WKWebView.
    static func printDocument(model: ReaderModel) {
        guard let webView = model.webView, let window = webView.window else { return }
        let operation = webView.printOperation(with: makePrintInfo())
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private static func makePrintInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 36
        info.bottomMargin = 44
        info.leftMargin = 36
        info.rightMargin = 36
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        return info
    }

    // MARK: - Standalone-HTML helpers

    private static func inlineThemeCSS(into html: String) -> String {
        guard let cssURL = Bundle.main.url(forResource: "theme", withExtension: "css", subdirectory: "web"),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else { return html }
        // Bundled fonts can't ship inside a single file; fall back to system faces.
        let standalone = css.replacingOccurrences(
            of: #"url\(\"fonts/[^\"]+\"\) format\(\"woff2-variations\"\)"#,
            with: "local(\"Helvetica Neue\")",
            options: .regularExpression
        )
        return html.replacingOccurrences(
            of: #"<link rel="stylesheet" href="theme.css">"#,
            with: "<style>\n\(standalone)\n</style>"
        )
    }

    private static func inlineKatexCSS(into html: String) -> String {
        guard html.contains("vendor/katex/katex.min.css"),
              let cssURL = Bundle.main.url(forResource: "katex.min", withExtension: "css", subdirectory: "web/vendor/katex"),
              let css = try? String(contentsOf: cssURL, encoding: .utf8) else { return html }
        return html.replacingOccurrences(
            of: #"<link rel="stylesheet" href="vendor/katex/katex.min.css">"#,
            with: "<style>\n\(css)\n</style>"
        )
    }

    /// Rewrites `doc-asset:///…` image sources to data: URIs so the exported
    /// file stands alone. Bounded so a screenshot-heavy doc can't balloon the
    /// export into the gigabytes.
    private static func inlineDocAssets(into html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"src="doc-asset://(/[^"]*)""#) else { return html }
        let mutable = NSMutableString(string: html)
        var budget = 64 * 1024 * 1024
        // Replace back-to-front so earlier ranges stay valid.
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: mutable.length)).reversed()
        for match in matches {
            let encodedPath = mutable.substring(with: match.range(at: 1))
            let path = encodedPath.removingPercentEncoding ?? encodedPath
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  data.count <= budget else { continue }
            budget -= data.count
            let mime = DocAssetSchemeHandler.mimeType(for: (path as NSString).pathExtension)
            mutable.replaceCharacters(
                in: match.range,
                with: "src=\"data:\(mime);base64,\(data.base64EncodedString())\""
            )
        }
        return mutable as String
    }

    private static func suggestedName(model: ReaderModel, ext: String) -> String {
        let base = model.fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        return base + "." + ext
    }
}
