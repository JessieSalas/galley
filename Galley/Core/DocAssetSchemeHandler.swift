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

    /// WebKit raises an NSException if a task is completed after it was
    /// stopped — which happens routinely when a live reload replaces the DOM
    /// while images are still in flight. Track live tasks and bail quietly.
    private var liveTasks = Set<ObjectIdentifier>()
    private let lock = NSLock()

    private func isLive(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return liveTasks.contains(ObjectIdentifier(task))
    }

    private func retire(_ task: WKURLSchemeTask) {
        lock.lock()
        liveTasks.remove(ObjectIdentifier(task))
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        lock.lock()
        liveTasks.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()

        let path = url.path.removingPercentEncoding ?? url.path
        let standardized = (path as NSString).standardizingPath
        let fileURL = URL(fileURLWithPath: standardized)

        DispatchQueue.global(qos: .userInitiated).async { [documentURL, weak self] in
            let allowed =
                standardized == documentURL?.path
                || standardized.hasPrefix((documentURL?.deletingLastPathComponent().path ?? "\u{0}") + "/")
                || FolderAccessManager.shared.canRead(path: standardized)

            let data = allowed ? (try? Data(contentsOf: fileURL)) : nil

            DispatchQueue.main.async {
                guard let self, self.isLive(urlSchemeTask) else { return }
                defer { self.retire(urlSchemeTask) }
                guard let data else {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                let response = URLResponse(
                    url: url,
                    mimeType: Self.mimeType(for: fileURL.pathExtension),
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        retire(urlSchemeTask)
    }

    static func mimeType(for ext: String) -> String {
        if let ut = UTType(filenameExtension: ext.lowercased()),
           let mime = ut.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
