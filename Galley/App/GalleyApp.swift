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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard NSDocumentController.shared.documents.isEmpty else { return }
            if !UserDefaults.standard.bool(forKey: "galley.hasLaunchedBefore") {
                UserDefaults.standard.set(true, forKey: "galley.hasLaunchedBefore")
                WelcomeOpener.openWelcome()
            }
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
    static func openWelcome() {
        guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "md", subdirectory: "Samples") else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
