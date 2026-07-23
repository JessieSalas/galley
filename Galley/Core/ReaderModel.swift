import AppKit
import WebKit
import Combine

struct TOCItem: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}

struct DocStats: Equatable {
    var words = 0
    var chars = 0
    var minutes = 0
    var tokens = 0
}

/// One per document window. Owns the markdown text, pushes renders into the
/// web layer, receives TOC/stats/scroll back, and reacts to disk changes.
@MainActor
final class ReaderModel: NSObject, ObservableObject {

    // Published UI state
    @Published var toc: [TOCItem] = []
    @Published var stats = DocStats()
    @Published var activeHeadingID: String?
    @Published var needsFolderAccess = false
    @Published var findBarVisible = false
    @Published var findQuery = ""
    @Published var findMisses = false
    @Published var presenting = false
    @Published var zoomSteps = 0
    @Published var isWatching = false

    let fileURL: URL?
    private(set) var markdown: String

    weak var webView: WKWebView?
    let schemeHandler = DocAssetSchemeHandler()

    private var webReady = false
    private var watcher: FileWatcher?
    private var defaultsObserver: AnyCancellable?
    private var fullScreenObservers: [NSObjectProtocol] = []

    init(text: String, fileURL: URL?) {
        self.markdown = text
        self.fileURL = fileURL
        super.init()
        schemeHandler.documentURL = fileURL
        UserDefaults.registerGalleyDefaults()

        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.pushOptions() }

        // Follow the system light/dark switch when the theme is "System".
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        if UserDefaults.standard.bool(forKey: SettingsKeys.liveReload), let url = fileURL {
            watcher = FileWatcher(
                url: url,
                onChange: { [weak self] in self?.reloadFromDisk() },
                onInvalidate: { [weak self] in self?.isWatching = false }
            )
            isWatching = true
        }
    }

    @objc private func systemAppearanceChanged() {
        // NSApp.effectiveAppearance updates a beat after the notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pushOptions()
        }
    }

    func teardown() {
        watcher?.stop()
        watcher = nil
        saveScrollPosition()
        for o in fullScreenObservers { NotificationCenter.default.removeObserver(o) }
        fullScreenObservers = []
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Web lifecycle

    func attach(webView: WKWebView) {
        self.webView = webView
        observeFullScreen(of: webView)
    }

    func handleWebReady() {
        webReady = true
        pushOptions()
        pushContent(isReload: false)
    }

    private func js(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              var s = String(data: data, encoding: .utf8) else { return "null" }
        // JSON is valid JS except these two separators.
        s = s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        s = s.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return s
    }

    private struct LoadPayload: Encodable {
        var markdown: String
        var docDir: String?
        var isReload: Bool
        var followTail: Bool
        var showFrontMatter: Bool
        var typographer: Bool
    }

    private struct OptionsPayload: Encodable {
        var appearance: String
        var typeface: String
        var measure: Int
        var scale: Double
        var allowRemote: Bool
        var presenting: Bool
    }

    private func effectiveAppearance() -> String {
        let pref = Appearance(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.appearance) ?? "") ?? .system
        switch pref {
        case .paper: return "paper"
        case .ink: return "ink"
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? "ink" : "paper"
        }
    }

    func pushOptions() {
        applyWindowAppearance()
        guard webReady else { return }
        let d = UserDefaults.standard
        let scale = d.double(forKey: SettingsKeys.textScale) * pow(1.1, Double(zoomSteps))
        let payload = OptionsPayload(
            appearance: effectiveAppearance(),
            typeface: d.string(forKey: SettingsKeys.typeface) ?? "default",
            measure: d.integer(forKey: SettingsKeys.measure),
            scale: min(max(scale, 0.55), 3.0),
            allowRemote: d.bool(forKey: SettingsKeys.allowRemote),
            presenting: presenting
        )
        js("Reader.applyOptions(\(Self.jsonString(payload)))")
        webView?.underPageBackgroundColor = payload.appearance == "ink"
            ? NSColor(red: 0.090, green: 0.086, blue: 0.059, alpha: 1)
            : NSColor(red: 0.945, green: 0.925, blue: 0.886, alpha: 1)
        applyRemotePolicy(allowRemote: payload.allowRemote)
        applyWindowAppearance()
    }

    /// The app chrome (titlebar, sidebar, popovers) follows the reading theme,
    /// so Ink never sits under a bright toolbar.
    private func applyWindowAppearance() {
        let pref = Appearance(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.appearance) ?? "") ?? .system
        switch pref {
        case .system: NSApp.appearance = nil
        case .paper: NSApp.appearance = NSAppearance(named: .aqua)
        case .ink: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Native backstop for "Load images from the web" — a compiled content
    /// rule list guarantees zero network requests when the toggle is off,
    /// even for raw HTML the JS sanitizer might not anticipate.
    private static var blockRemoteRuleList: WKContentRuleList?
    private var remotePolicyApplied: Bool?

    private func applyRemotePolicy(allowRemote: Bool) {
        guard let controller = webView?.configuration.userContentController else { return }
        guard remotePolicyApplied != allowRemote else { return }
        remotePolicyApplied = allowRemote

        if allowRemote {
            if let list = Self.blockRemoteRuleList {
                controller.remove(list)
            }
            return
        }
        if let list = Self.blockRemoteRuleList {
            controller.add(list)
            return
        }
        let rules = """
        [{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "galley.block-remote",
            encodedContentRuleList: rules
        ) { list, _ in
            guard let list else { return }
            Task { @MainActor in
                Self.blockRemoteRuleList = list
                if self.remotePolicyApplied == false {
                    controller.add(list)
                }
            }
        }
    }

    func pushContent(isReload: Bool) {
        guard webReady else { return }
        let d = UserDefaults.standard
        let payload = LoadPayload(
            markdown: markdown,
            docDir: fileURL?.deletingLastPathComponent().path,
            isReload: isReload,
            followTail: isReload && d.bool(forKey: SettingsKeys.followTail),
            showFrontMatter: (d.string(forKey: SettingsKeys.frontMatter) ?? "card") == "card",
            typographer: d.bool(forKey: SettingsKeys.smartTypography)
        )
        js("Reader.load(\(Self.jsonString(payload)))")
    }

    // MARK: - Live reload

    private func reloadFromDisk() {
        guard let url = fileURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let text = MarkdownDocument.decode(data)
        guard text != markdown else { return }
        markdown = text
        pushContent(isReload: true)
    }

    // MARK: - Bridge messages from JS

    func handleMessage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "ready":
            handleWebReady()
        case "toc":
            if let items = body["items"] as? [[String: Any]] {
                var seen = Set<String>()
                toc = items.compactMap { item in
                    guard let level = item["level"] as? Int,
                          let text = item["text"] as? String,
                          let id = item["id"] as? String, !id.isEmpty else { return nil }
                    // List identity must be unique even with duplicate headings.
                    var unique = id
                    var n = 1
                    while seen.contains(unique) { n += 1; unique = "\(id)-dup\(n)" }
                    seen.insert(unique)
                    return TOCItem(id: unique, level: level, text: text)
                }
            }
        case "stats":
            stats = DocStats(
                words: body["words"] as? Int ?? 0,
                chars: body["chars"] as? Int ?? 0,
                minutes: body["minutes"] as? Int ?? 0,
                tokens: body["tokens"] as? Int ?? 0
            )
        case "scroll":
            if let fraction = body["fraction"] as? Double {
                pendingScrollFraction = fraction
            }
            if let heading = body["activeHeading"] as? String,
               Date() >= suppressActiveHeadingUntil {
                activeHeadingID = heading.isEmpty ? nil : heading
            }
        case "rendered":
            let isReload = body["isReload"] as? Bool ?? false
            if !isReload { restoreScrollPosition() }
        case "link":
            if let href = body["href"] as? String {
                openLink(href)
            }
        case "assetMissing":
            offerFolderAccessIfUseful()
        default:
            break
        }
    }

    // MARK: - Links

    private func openLink(_ href: String) {
        if let url = URL(string: href), let scheme = url.scheme?.lowercased() {
            if ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
                return
            }
            if scheme == "file" {
                openLocalDocument(at: url)
                return
            }
            if scheme == "doc-asset" { return }
        }
        // Relative link → resolve against the document folder. The href
        // arrives percent-encoded from markdown-it, so decode exactly once.
        guard let base = fileURL?.deletingLastPathComponent() else { return }
        let parts = href.split(separator: "#", maxSplits: 1)
        var relPath = String(parts.first ?? "")
        relPath = relPath.removingPercentEncoding ?? relPath
        guard !relPath.isEmpty else { return }
        let resolved = URL(fileURLWithPath: relPath, relativeTo: base).standardizedFileURL
        openLocalDocument(at: resolved)
    }

    private func openLocalDocument(at url: URL) {
        let markdownExts = ["md", "markdown", "mdown", "mkdn", "mkd", "txt"]
        guard markdownExts.contains(url.pathExtension.lowercased()) else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if FileManager.default.isReadableFile(atPath: url.path) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
            offerFolderAccess(reason: .link(url))
        }
    }

    enum FolderAccessReason: Equatable {
        case images
        case link(URL)
    }

    @Published var folderAccessReason: FolderAccessReason = .images
    private var bannerDismissedForThisDocument = false

    func dismissFolderBanner() {
        needsFolderAccess = false
        bannerDismissedForThisDocument = true
    }

    private func offerFolderAccess(reason: FolderAccessReason) {
        guard !bannerDismissedForThisDocument else { return }
        guard let dir = fileURL?.deletingLastPathComponent() else { return }
        guard !FolderAccessManager.shared.canRead(path: dir.path) else { return }
        folderAccessReason = reason
        needsFolderAccess = true
    }

    private func offerFolderAccessIfUseful() {
        offerFolderAccess(reason: .images)
    }

    func grantFolderAccess() {
        guard let dir = fileURL?.deletingLastPathComponent() else { return }
        let reason = folderAccessReason
        FolderAccessManager.shared.requestAccess(
            startingAt: dir,
            message: "Galley needs permission to read this folder to show the document's images and open linked files."
        ) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.needsFolderAccess = false
                guard granted else { return }
                self.pushContent(isReload: true)
                // Finish what the user was doing: a link click that was
                // blocked on permissions now completes.
                if case .link(let url) = reason {
                    self.openLocalDocument(at: url)
                }
            }
        }
    }

    // MARK: - Scroll memory

    private var pendingScrollFraction: Double?

    private func scrollKey() -> String? {
        fileURL.map { "galley.scroll::" + $0.path }
    }

    func saveScrollPosition() {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.restoreScroll),
              let key = scrollKey(), let fraction = pendingScrollFraction else { return }
        UserDefaults.standard.set(fraction, forKey: key)
    }

    private func restoreScrollPosition() {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.restoreScroll),
              let key = scrollKey() else { return }
        let saved = UserDefaults.standard.double(forKey: key)
        if saved > 0.001 {
            js("Reader.setScrollFraction(\(saved))")
        }
    }

    // MARK: - Find

    func find(forward: Bool) {
        guard !findQuery.isEmpty, let webView else { return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.caseSensitive = false
        config.wraps = true
        webView.find(findQuery, configuration: config) { [weak self] result in
            Task { @MainActor in self?.findMisses = !result.matchFound }
        }
    }

    func dismissFind() {
        findBarVisible = false
        findQuery = ""
        findMisses = false
        js("window.getSelection()?.removeAllRanges()")
    }

    // MARK: - View commands

    func zoom(steps: Int) {
        zoomSteps = steps == 0 ? 0 : min(max(zoomSteps + steps, -6), 10)
        if steps == 0 {
            webView?.magnification = 1
        }
        pushOptions()
    }

    /// Sidebar clicks drive a smooth scroll; ignore scroll-derived heading
    /// updates until it settles so the selection doesn't flicker or snap back.
    private(set) var suppressActiveHeadingUntil = Date.distantPast

    func selectHeading(_ id: String) {
        activeHeadingID = id
        suppressActiveHeadingUntil = Date().addingTimeInterval(0.8)
        scrollToHeading(id)
    }

    func togglePresentation() {
        presenting.toggle()
        pushOptions()
        guard let window = webView?.window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if presenting != isFullScreen {
            window.toggleFullScreen(nil)
        }
    }

    private func observeFullScreen(of webView: WKWebView) {
        guard fullScreenObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let exit = center.addObserver(
            forName: NSWindow.willExitFullScreenNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let window = self.webView?.window,
                      (note.object as? NSWindow) === window, self.presenting else { return }
                self.presenting = false
                self.pushOptions()
            }
        }
        fullScreenObservers = [exit]
    }

    func scrollToHeading(_ id: String) {
        // Strip the disambiguation suffix used for List identity.
        let real = id.replacingOccurrences(of: #"-dup\d+$"#, with: "", options: .regularExpression)
        js("Reader.scrollToAnchor(\(Self.jsonString(real)))")
    }

    // MARK: - Copy / export

    var badge: String? {
        guard let name = fileURL?.lastPathComponent.lowercased() else { return nil }
        switch name {
        case "claude.md", "agents.md": return "Agent instructions"
        case "skill.md": return "Agent skill"
        case "llms.txt": return "LLM index"
        case "readme.md": return "Read me"
        default: return nil
        }
    }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func copyForAI() {
        var text = markdown
        if let path = fileURL?.path {
            text = "<!-- file: \(path) -->\n\n" + text
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyHTML() {
        webView?.evaluateJavaScript("document.getElementById('content').innerHTML") { [markdown] result, _ in
            let html = (result as? String) ?? ""
            DispatchQueue.main.async {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(html, forType: .html)
                pb.setString(markdown, forType: .string)
            }
        }
    }

    func reloadNow() {
        if fileURL != nil {
            reloadFromDisk()
        } else {
            pushContent(isReload: true)
        }
    }
}
