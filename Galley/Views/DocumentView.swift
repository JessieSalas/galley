import SwiftUI

struct DocumentView: View {
    @StateObject private var model: ReaderModel
    @State private var sidebarVisibility = NavigationSplitViewVisibility.detailOnly
    @State private var showInfo = false
    @State private var showTypePopover = false

    init(document: MarkdownDocument, fileURL: URL?) {
        _model = StateObject(wrappedValue: ReaderModel(text: document.text, fileURL: fileURL))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            OutlineSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
        } detail: {
            readerArea
        }
        .navigationSubtitle(model.badge ?? "")
        .toolbar { toolbarContent }
        .focusedSceneValue(\.readerModel, model)
        .onDisappear { model.saveScrollPosition() }
    }

    private var readerArea: some View {
        ZStack(alignment: .top) {
            ReaderWebView(model: model)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 8) {
                if model.findBarVisible {
                    FindBar(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if model.needsFolderAccess {
                    FolderAccessBanner(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .animation(.easeOut(duration: 0.18), value: model.findBarVisible)
            .animation(.easeOut(duration: 0.18), value: model.needsFolderAccess)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isWatching {
                LiveDot()
                    .help("Watching for changes — the page updates when the file is saved")
            }

            Button {
                showTypePopover.toggle()
            } label: {
                Label("Appearance", systemImage: "textformat.size")
            }
            .help("Theme, typeface, and layout")
            .popover(isPresented: $showTypePopover, arrowEdge: .bottom) {
                AppearancePopover(model: model)
            }

            Button {
                showInfo.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            .help("Document statistics")
            .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                InfoPopover(model: model)
            }

            Menu {
                ExportCommands(model: model)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Export and copy")
        }
    }
}

// MARK: - Sidebar

struct OutlineSidebar: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        List(selection: Binding(
            get: { model.activeHeadingID },
            set: { newValue in
                if let id = newValue { model.scrollToHeading(id) }
            }
        )) {
            if model.toc.isEmpty {
                Text("No headings")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                Section("Contents") {
                    ForEach(model.toc) { item in
                        Text(item.text)
                            .lineLimit(2)
                            .font(item.level <= 1 ? .body.weight(.semibold) : .callout)
                            .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                            .tag(item.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Find bar

struct FindBar: View {
    @ObservedObject var model: ReaderModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in document", text: $model.findQuery)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.find(forward: true) }
                .onChange(of: model.findQuery) { _, _ in
                    model.findMisses = false
                }
            if model.findMisses {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button { model.find(forward: false) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            Button { model.find(forward: true) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            Button("Done") { model.dismissFind() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear { focused = true }
    }
}

// MARK: - Folder access banner

struct FolderAccessBanner: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("Some images live next to this file.")
                .font(.callout)
            Button("Show Images…") { model.grantFolderAccess() }
                .controlSize(.small)
            Button {
                model.needsFolderAccess = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

// MARK: - Live indicator

struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.21, green: 0.84, blue: 0.76))
            .frame(width: 7, height: 7)
            .opacity(pulse ? 0.5 : 1)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityLabel("Live — watching file for changes")
    }
}

// MARK: - Appearance popover (the “Aa” panel)

struct AppearancePopover: View {
    @ObservedObject var model: ReaderModel
    @AppStorage(SettingsKeys.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(SettingsKeys.typeface) private var typeface = Typeface.standard.rawValue
    @AppStorage(SettingsKeys.measure) private var measure = Measure.normal.rawValue
    @AppStorage(SettingsKeys.textScale) private var textScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { a in
                    Text(a.label).tag(a.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Typeface", selection: $typeface) {
                ForEach(Typeface.allCases) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Text("Size")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $textScale, in: 0.8...1.6, step: 0.05)
                Text(String(format: "%.0f%%", textScale * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            Picker("Line width", selection: $measure) {
                ForEach(Measure.allCases) { m in
                    Text(m.label).tag(m.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - Info popover

struct InfoPopover: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow("Words", model.stats.words.formatted())
            statRow("Characters", model.stats.chars.formatted())
            statRow("Reading time", "\(model.stats.minutes) min")
            statRow("≈ Tokens", model.stats.tokens.formatted())
            if let url = model.fileURL {
                Divider().padding(.vertical, 2)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        }
        .padding(16)
        .frame(width: 220, alignment: .leading)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

// MARK: - Export commands (shared by toolbar menu and File menu)

struct ExportCommands: View {
    let model: ReaderModel

    var body: some View {
        Button("Export as PDF…") { Exporter.exportPDF(model: model) }
        Button("Export as HTML…") { Exporter.exportHTML(model: model) }
        Divider()
        Button("Copy Markdown") { model.copyMarkdown() }
        Button("Copy for AI") { model.copyForAI() }
        Button("Copy as HTML") { model.copyHTML() }
    }
}
