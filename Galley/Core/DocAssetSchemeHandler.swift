import WebKit
import UniformTypeIdentifiers

/// Serves `doc-asset:///absolute/path` requests for images and media that a
/// document references with relative paths. Reads happen in Swift, under
/// whatever access the sandbox has granted (the document itself via Launch
/// Services, or a folder the user granted in FolderAccessManager).
final class DocAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "doc-asset"

    /// The open document's own URL — always readable, and its inode may be
    /// re-granted on live reload.
    var documentURL: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path.removingPercentEncoding ?? url.path
        let standardized = (path as NSString).standardizingPath
        let fileURL = URL(fileURLWithPath: standardized)

        DispatchQueue.global(qos: .userInitiated).async { [documentURL] in
            let allowed =
                standardized == documentURL?.path
                || standardized.hasPrefix((documentURL?.deletingLastPathComponent().path ?? "\u{0}") + "/")
                || FolderAccessManager.shared.canRead(path: standardized)

            guard allowed, let data = try? Data(contentsOf: fileURL) else {
                DispatchQueue.main.async {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                }
                return
            }
            let mime = Self.mimeType(for: fileURL.pathExtension)
            let response = URLResponse(
                url: url,
                mimeType: mime,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            DispatchQueue.main.async {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Reads are quick; nothing to cancel.
    }

    static func mimeType(for ext: String) -> String {
        if let ut = UTType(filenameExtension: ext.lowercased()),
           let mime = ut.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
