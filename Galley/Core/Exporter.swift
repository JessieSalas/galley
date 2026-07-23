import AppKit
import WebKit
import UniformTypeIdentifiers

/// PDF, HTML, and print pipelines. All exports go through the user's save
/// panel (the sandbox grants write access to the chosen location).
@MainActor
enum Exporter {

    static func exportPDF(model: ReaderModel) {
        guard let webView = model.webView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName(model: model, ext: "pdf")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            webView.createPDF(configuration: .init()) { result in
                if case .success(let data) = result {
                    try? data.write(to: url)
                }
            }
        }
    }

    static func exportHTML(model: ReaderModel) {
        guard let webView = model.webView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedName(model: model, ext: "html")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            webView.evaluateJavaScript("Reader.exportHTML()") { result, _ in
                guard var html = result as? String else { return }
                // Inline the stylesheet so the exported file stands alone.
                if let cssURL = Bundle.main.url(forResource: "theme", withExtension: "css", subdirectory: "web"),
                   let css = try? String(contentsOf: cssURL, encoding: .utf8) {
                    let standalone = css
                        .replacingOccurrences(
                            of: #"url\(\"fonts/[^\"]+\"\) format\(\"woff2-variations\"\)"#,
                            with: "local(\"Helvetica Neue\")",
                            options: .regularExpression
                        )
                    html = html.replacingOccurrences(
                        of: #"<link rel="stylesheet" href="theme.css">"#,
                        with: "<style>\n\(standalone)\n</style>"
                    )
                }
                try? html.data(using: .utf8)?.write(to: url)
            }
        }
    }

    /// Paginated print. The explicit frame assignment before running works
    /// around a macOS 26 (Tahoe) crash in NSPrintOperation with WKWebView.
    static func printDocument(model: ReaderModel) {
        guard let webView = model.webView, let window = webView.window else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 36
        info.bottomMargin = 44
        info.leftMargin = 36
        info.rightMargin = 36
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private static func suggestedName(model: ReaderModel, ext: String) -> String {
        let base = model.fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        return base + "." + ext
    }
}
