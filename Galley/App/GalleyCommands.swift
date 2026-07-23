import SwiftUI

struct ReaderModelKey: FocusedValueKey {
    typealias Value = ReaderModel
}

extension FocusedValues {
    var readerModel: ReaderModel? {
        get { self[ReaderModelKey.self] }
        set { self[ReaderModelKey.self] = newValue }
    }
}

/// Menu items whose title/enabled state track the frontmost model's
/// @Published values. Two traps live here: @FocusedValue goes nil while the
/// editor's NSTextView holds first responder, and Commands never re-evaluate
/// when a model publishes. ActiveModelTracker solves both — AppKit-driven
/// currency, with the model's objectWillChange forwarded through.
private struct SaveMenuItem: View {
    @ObservedObject var tracker = ActiveModelTracker.shared
    var body: some View {
        Button("Save") { tracker.current?.saveDraft() }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!(tracker.current?.isEditing == true && tracker.current?.isDirty == true))
    }
}

private struct EditToggleMenuItem: View {
    @ObservedObject var tracker = ActiveModelTracker.shared
    var body: some View {
        Button(tracker.current?.isEditing == true ? "Done Editing" : "Edit Markdown") {
            guard let model = tracker.current else { return }
            model.isEditing ? model.requestExitEdit() : model.enterEdit()
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(tracker.current?.canEdit != true)
    }
}

private struct PresentToggleMenuItem: View {
    @ObservedObject var tracker = ActiveModelTracker.shared
    var body: some View {
        Button(tracker.current?.presenting == true ? "Exit Presentation" : "Present") {
            tracker.current?.togglePresentation()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(tracker.current == nil)
    }
}

struct GalleyCommands: Commands {
    @AppStorage(SettingsKeys.theme) private var themeID = "thesis"
    @AppStorage(SettingsKeys.mode) private var mode = AppearanceMode.system.rawValue
    @AppStorage(SettingsKeys.measure) private var measure = Measure.normal.rawValue
    /// Observed so plain items' disabled states refresh as windows come and go.
    @ObservedObject private var tracker = ActiveModelTracker.shared

    /// Read at action time, never captured — always the frontmost document.
    private var model: ReaderModel? { tracker.current }

    var body: some Commands {
        // Viewer: no "New Document"; the system supplies Open/Open Recent.
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .saveItem) {
            // Replacing this group drops the system Close item — restore it,
            // routed through performClose so the dirty-edit guard still runs.
            Button("Close") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: .command)

            SaveMenuItem()

            Divider()

            // ⌘E stays free: it's the system-wide "Use Selection for Find".
            Button("Export as PDF…") {
                if let model { Exporter.exportPDF(model: model) }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(model == nil)

            Button("Export as HTML…") {
                if let model { Exporter.exportHTML(model: model) }
            }
            .keyboardShortcut("e", modifiers: [.command, .option, .shift])
            .disabled(model == nil)

            Divider()

            Button("Print…") {
                if let model { Exporter.printDocument(model: model) }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(model == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            EditToggleMenuItem()
            Divider()
            Button("Copy Markdown") { model?.copyMarkdown() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Copy for AI") { model?.copyForAI() }
                .keyboardShortcut("c", modifiers: [.command, .shift, .option])
                .disabled(model == nil)
            Button("Copy as HTML") { model?.copyHTML() }
                .disabled(model == nil)
            Divider()
            Button("Find…") {
                guard let model else { return }
                if model.isEditing {
                    model.editorTextView?.performFindAction(.showFindInterface)
                } else {
                    model.findBarVisible = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model == nil)
            Button("Find Next") {
                guard let model else { return }
                if model.isEditing {
                    model.editorTextView?.performFindAction(.nextMatch)
                } else if model.findBarVisible {
                    model.find(forward: true)
                } else {
                    model.findBarVisible = true
                }
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(model == nil)
            Button("Find Previous") {
                guard let model else { return }
                if model.isEditing {
                    model.editorTextView?.performFindAction(.previousMatch)
                } else {
                    model.find(forward: false)
                }
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(model == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Actual Size") { model?.zoom(steps: 0) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model == nil)
            Button("Zoom In") { model?.zoom(steps: 1) }
                .keyboardShortcut("=", modifiers: .command) // ⌘= — what ⌘+ physically is on ANSI keyboards
                .disabled(model == nil)
            Button("Zoom Out") { model?.zoom(steps: -1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model == nil)

            Divider()

            Picker("Theme", selection: $themeID) {
                ForEach(ThemeStore.builtIns) { t in
                    Text(t.name).tag(t.id)
                }
            }
            Picker("Mode", selection: $mode) {
                ForEach(AppearanceMode.allCases) { m in
                    Text(m.label).tag(m.rawValue)
                }
            }
            Picker("Line Width", selection: $measure) {
                ForEach(Measure.allCases) { m in
                    Text(m.label).tag(m.rawValue)
                }
            }

            Divider()

            Button("Reload") { model?.reloadNow() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model == nil)

            PresentToggleMenuItem()
        }

        CommandGroup(replacing: .help) {
            Button("Welcome to Galley") {
                WelcomeOpener.openWelcome()
            }
            Button("Feature Tour") {
                if let url = Bundle.main.url(forResource: "Tour", withExtension: "md", subdirectory: "Samples") {
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
            Divider()
            Link("Galley on GitHub", destination: URL(string: "https://github.com/thesis-labs/galley")!)
            Link("Thesis Labs", destination: URL(string: "https://thesis.do")!)
        }
    }
}
