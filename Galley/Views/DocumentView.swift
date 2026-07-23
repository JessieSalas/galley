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
        .navigationSubtitle(subtitle)
        .toolbar { toolbarContent }
        .focusedSceneValue(\.readerModel, model)
        .onDisappear { model.saveScrollPosition() }
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.isEditing { parts.append("Editing") }
        if let badge = model.badge { parts.append(badge) }
        return parts.joined(separator: " · ")
    }

    private var readerArea: some View {
        ZStack(alignment: .top) {
            // Both layers stay alive at all times — the web view so its scroll
            // position and rendered state survive the round trip, the editor
            // so its undo stack does too. Only opacity/hit-testing swap.
            ReaderWebView(model: model)
                .ignoresSafeArea(edges: .bottom)
                .opacity(model.isEditing ? 0 : 1)
                .allowsHitTesting(!model.isEditing)

            MarkdownEditorView(model: model)
                .opacity(model.isEditing ? 1 : 0)
                .allowsHitTesting(model.isEditing)

            VStack(spacing: 8) {
                if model.findBarVisible && !model.isEditing {
                    FindBar(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if model.needsFolderAccess && !model.isEditing {
                    FolderAccessBanner(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if model.externalChangePending && model.isEditing {
                    ExternalChangeBanner(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .animation(.easeOut(duration: 0.18), value: model.findBarVisible)
            .animation(.easeOut(duration: 0.18), value: model.needsFolderAccess)
            .animation(.easeOut(duration: 0.18), value: model.externalChangePending)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The live dot gets its own item with a real frame — inside the grouped
        // pill the 7 pt circle ends up crammed against the first button.
        ToolbarItem(placement: .primaryAction) {
            if model.isWatching && !model.isEditing {
                LiveDot()
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 2)
                    .help("Watching for changes — the page updates when the file is saved")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {

            Button {
                showTypePopover.toggle()
            } label: {
                Label("Appearance", systemImage: "textformat.size")
            }
            .help("Theme, typeface, and layout")
            .popover(isPresented: $showTypePopover, arrowEdge: .bottom) {
                AppearancePopover(model: model)
            }

            if !model.isEditing {
                Button {
                    showInfo.toggle()
                } label: {
                    Label("Info", systemImage: "info.circle")
                }
                .help("Document statistics")
                .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                    InfoPopover(model: model)
                }
            }

            if model.isEditing {
                Button {
                    model.saveDraft()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .help("Save changes (⌘S)")
                .disabled(!model.isDirty)
            }

            Button {
                if model.isEditing {
                    model.requestExitEdit()
                } else {
                    model.enterEdit()
                }
            } label: {
                Label(model.isEditing ? "Done Editing" : "Edit Markdown", systemImage: "square.and.pencil")
            }
            .symbolVariant(model.isEditing ? .fill : .none)
            .tint(model.isEditing ? Color.accentColor : nil)
            .help(model.canEdit
                  ? (model.isEditing ? "Done Editing (⌘⇧E)" : "Edit Markdown (⌘⇧E)")
                  : "This document can't be edited")
            .disabled(!model.canEdit)

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
                if let id = newValue { model.selectHeading(id) }
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

    private var message: String {
        switch model.folderAccessReason {
        case .images:
            "Galley doesn't have permission to read this document's folder, so its images can't load."
        case .link:
            "That link points to a file Galley doesn't have permission to read."
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.badge.clock")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
            Button("Grant Access…") { model.grantFolderAccess() }
                .controlSize(.small)
            Button {
                model.dismissFolderBanner()
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

// MARK: - External change banner (edit mode)

struct ExternalChangeBanner: View {
    @ObservedObject var model: ReaderModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            Text("This file changed on disk.")
                .font(.callout)
            Button("Use Disk Version") { model.adoptDiskVersion() }
                .controlSize(.small)
            Button("Keep Mine") { model.keepMineDismissDisk() }
                .controlSize(.small)
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
    @AppStorage(SettingsKeys.theme) private var themeID = "thesis"
    @AppStorage(SettingsKeys.mode) private var mode = AppearanceMode.system.rawValue
    @AppStorage(SettingsKeys.measure) private var measure = Measure.normal.rawValue
    @AppStorage(SettingsKeys.textScale) private var textScale = 1.0

    private var currentTheme: GalleyTheme { ThemeStore.theme(id: themeID) }

    /// Which palette variant (light/dark) is on screen right now, resolving
    /// "System" against the app's effective appearance — drives the swatch
    /// chips so they always show the theme as it actually looks.
    private var variant: ThemeStore.Variant {
        switch AppearanceMode(rawValue: mode) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .dark : .light
        }
    }

    private var spectralBinding: Binding<Bool> {
        Binding(
            get: { ThemeStore.overrides(for: themeID).spectral ?? currentTheme.spectral },
            set: { newValue in
                var overrides = ThemeStore.overrides(for: themeID)
                overrides.spectral = newValue == currentTheme.spectral ? nil : newValue
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ThemeStore.builtIns) { theme in
                    ThemeRow(theme: theme, isSelected: theme.id == themeID, variant: variant) {
                        themeID = theme.id
                    }
                }
            }

            Divider()

            Picker("Mode", selection: $mode) {
                ForEach(AppearanceMode.allCases) { m in
                    Text(m.label).tag(m.rawValue)
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

            Toggle("Spectral accents", isOn: spectralBinding)
                .toggleStyle(.switch)
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// One theme choice: name + blurb + a 3-swatch chip (bg / ink / accent) for
/// the variant currently on screen. Shared by the popover and Settings.
struct ThemeRow: View {
    let theme: GalleyTheme
    let isSelected: Bool
    let variant: ThemeStore.Variant
    let action: () -> Void

    private var palette: ThemePalette {
        ThemeStore.resolved(theme: theme, variant: variant).palette
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                swatch
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name).font(.callout.weight(.medium))
                    Text(theme.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var swatch: some View {
        HStack(spacing: 2) {
            chip(palette.bg)
            chip(palette.ink)
            chip(palette.accent)
        }
    }

    private func chip(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 10, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.08)))
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
