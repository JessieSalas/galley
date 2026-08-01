import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The Markdown UTI Apple is standardizing on (declared as imported in Info.plist).
    static let markdownDoc = UTType(importedAs: "net.daringfireball.markdown")
}

@main
struct GalleyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        UserDefaults.registerGalleyDefaults()
    }

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(document: configuration.document, fileURL: configuration.fileURL)
        }
        .commands {
            SidebarCommands()
            GalleyCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // First launch with nothing to open: show the Welcome document instead
        // of a bare open panel, so the very first impression is the product.
        checkForFirstLaunch(checksRemaining: 3)
    }

    /// `documents.isEmpty` right after launch is a proxy for "nothing was
    /// passed to open," not a guarantee — NSDocumentController's launch-time
    /// open is documented as asynchronous, so a single 0.3s check can catch
    /// a real document mid-open (slow/network volume) and show Welcome
    /// alongside it. A few spaced checks give a genuinely in-flight open a
    /// chance to land before committing either way.
    private func checkForFirstLaunch(checksRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard !UserDefaults.standard.bool(forKey: "galley.hasLaunchedBefore") else { return }
            guard NSDocumentController.shared.documents.isEmpty else {
                UserDefaults.standard.set(true, forKey: "galley.hasLaunchedBefore")
                return
            }
            guard checksRemaining > 1 else {
                UserDefaults.standard.set(true, forKey: "galley.hasLaunchedBefore")
                WelcomeOpener.openWelcome()
                return
            }
            self?.checkForFirstLaunch(checksRemaining: checksRemaining - 1)
        }
    }

    /// No untitled documents in a viewer; also suppresses the launch open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no windows offers the open panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSDocumentController.shared.openDocument(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum WelcomeOpener {
    static var url: URL? {
        Bundle.main.url(forResource: "Welcome", withExtension: "md", subdirectory: "Samples")
    }

    static func openWelcome() {
        guard let url else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// Used to gate the first-run onboarding sheet to the actual Welcome
    /// document, never a file the user opened themselves.
    static func isWelcome(_ candidate: URL?) -> Bool {
        guard let candidate, let url else { return false }
        return candidate.standardizedFileURL == url.standardizedFileURL
    }
}
