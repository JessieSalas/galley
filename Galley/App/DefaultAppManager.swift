import AppKit

/// Sets Galley as the default handler for Markdown files via the sanctioned
/// NSWorkspace API (macOS 12+), which covers every extension mapped to
/// `net.daringfireball.markdown` in one call — unlike Finder's "Change All,"
/// which only covers the one extension you right-clicked.
///
/// This is user-initiated only (a Settings button), never called on launch.
/// Sandboxed apps have been reported to hit a permErr from this API in some
/// configurations, so callers must handle failure and point back to the
/// manual Finder method rather than assume success.
enum DefaultAppManager {
    static func setGalleyAsDefault(completion: @escaping (Bool) -> Void) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .markdownDoc) { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        }
    }
}
