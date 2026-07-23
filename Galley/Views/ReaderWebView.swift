import SwiftUI
import WebKit

/// Hosts the WKWebView that renders the document. All chrome is native SwiftUI;
/// this view is just the page.
struct ReaderWebView: NSViewRepresentable {
    @ObservedObject var model: ReaderModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "reader")
        configuration.setURLSchemeHandler(model.schemeHandler, forURLScheme: DocAssetSchemeHandler.scheme)
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        webView.isInspectable = true
        #endif

        model.attach(webView: webView)

        if let templateURL = Bundle.main.url(forResource: "template", withExtension: "html", subdirectory: "web"),
           let webDir = Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true) {
            webView.loadFileURL(templateURL, allowingReadAccessTo: webDir)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
        coordinator.model?.teardown()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var model: ReaderModel?

        init(model: ReaderModel) {
            self.model = model
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "reader", let body = message.body as? [String: Any] else { return }
            Task { @MainActor in
                self.model?.handleMessage(body)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Only the bundled template may load as a page; the JS layer routes
            // every link through the native side.
            if url.isFileURL || url.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        /// target=_blank and window.open land here → hand to the default browser.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
