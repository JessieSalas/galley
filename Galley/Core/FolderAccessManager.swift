import AppKit

/// Remembers folders the user has granted read access to (security-scoped
/// bookmarks), so a document's local images render without re-asking.
final class FolderAccessManager {
    static let shared = FolderAccessManager()

    private let defaultsKey = "galley.folderBookmarks"
    /// Folders currently under an active security scope, path → URL.
    private var active: [String: URL] = [:]
    private let lock = NSLock()

    private init() {
        restoreAll()
    }

    private func bookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    private func restoreAll() {
        var store = bookmarks()
        var changed = false
        for (path, data) in store {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                store.removeValue(forKey: path)
                changed = true
                continue
            }
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                store[path] = fresh
                changed = true
            }
            if url.startAccessingSecurityScopedResource() {
                active[url.path] = url
            }
        }
        if changed {
            UserDefaults.standard.set(store, forKey: defaultsKey)
        }
    }

    var grantedFolders: [String] {
        lock.lock(); defer { lock.unlock() }
        return active.keys.sorted()
    }

    /// True if `path` lies inside any granted folder.
    func canRead(path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let normalized = (path as NSString).standardizingPath
        return active.keys.contains { normalized == $0 || normalized.hasPrefix($0 + "/") }
    }

    func remember(folder url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope) else { return }
        var store = bookmarks()
        store[url.path] = data
        UserDefaults.standard.set(store, forKey: defaultsKey)
        if url.startAccessingSecurityScopedResource() {
            lock.lock()
            active[url.path] = url
            lock.unlock()
        }
    }

    func revoke(path: String) {
        var store = bookmarks()
        store.removeValue(forKey: path)
        UserDefaults.standard.set(store, forKey: defaultsKey)
        lock.lock()
        if let url = active.removeValue(forKey: path) {
            url.stopAccessingSecurityScopedResource()
        }
        lock.unlock()
    }

    /// Asks the user to grant read access to a folder, pre-pointed at the
    /// document's directory. One panel, remembered forever.
    @MainActor
    func requestAccess(startingAt directory: URL, message: String, completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = message
        panel.prompt = "Grant Access"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            self?.remember(folder: url)
            completion(true)
        }
    }
}
