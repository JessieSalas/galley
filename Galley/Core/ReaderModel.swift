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

    // Edit mode
    @Published var isEditing = false
    @Published var draftText = "" {
        didSet { isDirty = draftText != markdown }
    }
    // Deliberately NOT mirrored into window.isDocumentEdited: in a
    // DocumentGroup app that flag belongs to NSDocument, which would try to
    // autosave our read-only document and complain. WindowCloseGuard covers
    // the close-with-unsaved-changes case instead.
    @Published var isDirty = false
    @Published var externalChangePending = false

    let fileURL: URL?
    private(set) var markdown: String

    weak var webView: WKWebView?
    /// Set by MarkdownEditorView while it's alive; used to route Find… into
    /// the text view's own find bar while editing.
    weak var editorTextView: NSTextView?
    let schemeHandler = DocAssetSchemeHandler()

    private var webReady = false
    private var watcher: FileWatcher?
    private var defaultsObserver: AnyCancellable?
    private var fullScreenObservers: [NSObjectProtocol] = []
    private var windowCloseGuard: WindowCloseGuard?
    private var window: NSWindow? { webView?.window }

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
        if let o = windowKeyObserver { NotificationCenter.default.removeObserver(o) }
        windowKeyObserver = nil
        DistributedNotificationCenter.default().removeObserver(self)
        ActiveModelTracker.shared.resign(self)
    }

    // MARK: - Web lifecycle

    private var windowKeyObserver: NSObjectProtocol?

    func attach(webView: WKWebView) {
        self.webView = webView
        observeFullScreen(of: webView)
        // Claim menu currency only when this window is actually key (or
        // nothing holds it yet) — a window restored in the background must
        // not steal commands from the document the user is looking at.
        if ActiveModelTracker.shared.current == nil || webView.window?.isKeyWindow == true {
            ActiveModelTracker.shared.adopt(self)
        }
        if windowKeyObserver == nil {
            windowKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    guard let self, let window = self.webView?.window,
                          (note.object as? NSWindow) === window else { return }
                    ActiveModelTracker.shared.adopt(self)
                }
            }
        }
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

    private struct FontsPayload: Encodable {
        var display: String
        var body: String
        var mono: String
    }

    private struct OptionsPayload: Encodable {
        var mode: String
        var palette: ThemePalette
        var fonts: FontsPayload
        var headingWeight: Int
        var spectral: Bool
        var measure: Int
        var scale: Double
        var allowRemote: Bool
        var presenting: Bool
    }

    /// Resolves "system" against the app's current effective appearance.
    private func effectiveMode() -> String {
        let pref = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.mode) ?? "") ?? .system
        switch pref {
        case .light: return "light"
        case .dark: return "dark"
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? "dark" : "light"
        }
    }

    func pushOptions() {
        applyWindowAppearance()
        guard webReady else { return }
        let d = UserDefaults.standard
        let scale = d.double(forKey: SettingsKeys.textScale) * pow(1.1, Double(zoomSteps))
        let mode = effectiveMode()
        let theme = ThemeStore.current()
        let resolved = ThemeStore.resolved(theme: theme, variant: mode == "dark" ? .dark : .light)
        let payload = OptionsPayload(
            mode: mode,
            palette: resolved.palette,
            fonts: FontsPayload(display: resolved.displayFont.css, body: resolved.bodyFont.css, mono: resolved.monoFont.css),
            headingWeight: resolved.headingWeight,
            spectral: resolved.spectral,
            measure: d.integer(forKey: SettingsKeys.measure),
            scale: min(max(scale, 0.55), 3.0),
            allowRemote: d.bool(forKey: SettingsKeys.allowRemote),
            presenting: presenting
        )
        js("Reader.applyOptions(\(Self.jsonString(payload)))")
        webView?.underPageBackgroundColor = NSColor(hex: resolved.palette.bg) ?? NSColor(red: 0.945, green: 0.925, blue: 0.886, alpha: 1)
        applyRemotePolicy(allowRemote: payload.allowRemote)
        applyWindowAppearance()
    }

    /// The app chrome (titlebar, sidebar, popovers) follows the reading theme,
    /// so a dark theme never sits under a bright toolbar.
    private func applyWindowAppearance() {
        let pref = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.mode) ?? "") ?? .system
        switch pref {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
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
        if isEditing {
            if isDirty {
                // Don't clobber unsaved edits — surface the conflict instead.
                externalChangePending = true
            } else {
                markdown = text
                draftText = text
            }
            return
        }
        markdown = text
        pushContent(isReload: true)
    }

    // MARK: - Edit mode

    /// Welcome/Tour and anything else read-only or unwritable stays view-only.
    var canEdit: Bool {
        guard let fileURL else { return false }
        guard FileManager.default.isWritableFile(atPath: fileURL.path) else { return false }
        guard !fileURL.path.hasPrefix(Bundle.main.bundleURL.path) else { return false }
        return true
    }

    func enterEdit() {
        guard canEdit, !isEditing else { return }
        isEditing = true
        draftText = markdown
        externalChangePending = false
        installWindowCloseGuard()
    }

    func saveDraft() {
        guard let fileURL else { return }
        do {
            // In place, not atomic: an atomic rename swaps the inode, which
            // NSDocument's proxy flags as an external "Edited" change.
            try Data(draftText.utf8).write(to: fileURL, options: [])
            markdown = draftText
            isDirty = false
            // Our write happens behind NSDocument's back; refresh its
            // bookkeeping so the title proxy doesn't flag "Edited".
            if let window, let document = NSDocumentController.shared.document(for: window) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                document.fileModificationDate = attrs?[.modificationDate] as? Date ?? Date()
            }
        } catch {
            guard let window else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't Save \u{201C}\(fileURL.lastPathComponent)\u{201D}"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
        }
    }

    func requestExitEdit() {
        guard isEditing else { return }
        guard isDirty else { finishExitingEdit(); return }
        guard let window else { finishExitingEdit(); return }
        presentUnsavedChangesAlert(in: window) { [weak self] in
            self?.saveDraft()
            self?.finishExitingEdit()
        } onDiscard: { [weak self] in
            guard let self else { return }
            self.draftText = self.markdown
            self.finishExitingEdit()
        } onCancel: {}
    }

    func adoptDiskVersion() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let text = MarkdownDocument.decode(data)
        markdown = text
        draftText = text
        externalChangePending = false
    }

    func keepMineDismissDisk() {
        externalChangePending = false
    }

    private func finishExitingEdit() {
        isEditing = false
        externalChangePending = false
        uninstallWindowCloseGuard()
        pushContent(isReload: true)
    }

    /// Shared by `requestExitEdit()` and `WindowCloseGuard` so the close-box
    /// prompt and the ⌘⇧E prompt read identically.
    fileprivate func presentUnsavedChangesAlert(
        in window: NSWindow,
        onSave: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Save changes to \u{201C}\(fileURL?.lastPathComponent ?? "this document")\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don\u{2019}t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: onSave()
            case .alertSecondButtonReturn: onDiscard()
            default: onCancel()
            }
        }
    }

    /// Installed as `window.delegate` while editing so closing the window
    /// with unsaved changes prompts instead of silently discarding them.
    /// Restored on exit.
    private func installWindowCloseGuard() {
        guard let window, windowCloseGuard == nil else { return }
        let guardDelegate = WindowCloseGuard()
        guardDelegate.original = window.delegate
        guardDelegate.model = self
        window.delegate = guardDelegate
        windowCloseGuard = guardDelegate
    }

    fileprivate func uninstallWindowCloseGuard() {
        guard let window, let guardDelegate = windowCloseGuard else { return }
        if window.delegate === guardDelegate {
            window.delegate = guardDelegate.original
        }
        windowCloseGuard = nil
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

/// Stands in for the document window's real delegate while edit mode is
/// active, so an unsaved close attempt gets the Save/Discard/Cancel prompt
/// instead of silently losing the draft. Forwards every other delegate call
/// straight through to `original` via `forwardingTarget(for:)`.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    weak var original: NSWindowDelegate?
    weak var model: ReaderModel?

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) == true)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        guard let original, original.responds(to: aSelector) else { return nil }
        return original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model, model.isEditing, model.isDirty else {
            return original?.windowShouldClose?(sender) ?? true
        }
        model.presentUnsavedChangesAlert(in: sender) {
            model.saveDraft()
            model.isEditing = false
            model.uninstallWindowCloseGuard()
            sender.close()
        } onDiscard: {
            model.draftText = model.markdown
            model.isEditing = false
            model.uninstallWindowCloseGuard()
            sender.close()
        } onCancel: {}
        return false
    }
}

/// The frontmost document's model, tracked via AppKit window-key events.
/// Menu commands read this instead of @FocusedValue, which goes nil whenever
/// an AppKit view (the markdown editor's NSTextView) holds first responder.
/// Forwards the current model's objectWillChange so menu item state stays live.
@MainActor
final class ActiveModelTracker: ObservableObject {
    static let shared = ActiveModelTracker()

    private(set) weak var current: ReaderModel? {
        willSet { objectWillChange.send() }
    }
    private var forwarder: AnyCancellable?

    func adopt(_ model: ReaderModel) {
        guard current !== model else { return }
        current = model
        forwarder = model.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func resign(_ model: ReaderModel) {
        guard current === model else { return }
        current = nil
        forwarder = nil
    }
}
