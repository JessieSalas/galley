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

struct GalleyCommands: Commands {
    @FocusedValue(\.readerModel) private var model
    @AppStorage(SettingsKeys.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(SettingsKeys.typeface) private var typeface = Typeface.standard.rawValue
    @AppStorage(SettingsKeys.measure) private var measure = Measure.normal.rawValue

    var body: some Commands {
        // Viewer: no "New Document".
        CommandGroup(replacing: .newItem) {
            Button("Open…") {
                NSDocumentController.shared.openDocument(nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Export as PDF…") {
                if let model { Exporter.exportPDF(model: model) }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model == nil)

            Button("Export as HTML…") {
                if let model { Exporter.exportHTML(model: model) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
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
                model?.findBarVisible = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Actual Size") { model?.zoom(steps: 0) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(model == nil)
            Button("Zoom In") { model?.zoom(steps: 1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(model == nil)
            Button("Zoom Out") { model?.zoom(steps: -1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(model == nil)

            Divider()

            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { a in
                    Text(a.label).tag(a.rawValue)
                }
            }
            Picker("Typeface", selection: $typeface) {
                ForEach(Typeface.allCases) { t in
                    Text(t.label).tag(t.rawValue)
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

            Button(model?.presenting == true ? "Exit Presentation" : "Present") {
                model?.togglePresentation()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(model == nil)
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
