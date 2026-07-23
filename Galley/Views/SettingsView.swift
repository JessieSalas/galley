import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "book") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
    }
}

private struct ReadingSettings: View {
    @AppStorage(SettingsKeys.liveReload) private var liveReload = true
    @AppStorage(SettingsKeys.followTail) private var followTail = true
    @AppStorage(SettingsKeys.restoreScroll) private var restoreScroll = true
    @AppStorage(SettingsKeys.smartTypography) private var smartTypography = true
    @AppStorage(SettingsKeys.frontMatter) private var frontMatter = FrontMatterDisplay.card.rawValue

    var body: some View {
        Form {
            Section {
                Toggle("Update when the file changes on disk", isOn: $liveReload)
                Toggle("Follow new content while at the bottom", isOn: $followTail)
                    .disabled(!liveReload)
                Text("When an AI agent or editor is still writing the document, Galley keeps up quietly — no jumps, no flashes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Remember reading position per document", isOn: $restoreScroll)
                Toggle("Smart typography (quotes, dashes, ellipses)", isOn: $smartTypography)
                Picker("Front matter", selection: $frontMatter) {
                    ForEach(FrontMatterDisplay.allCases) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                }
            }
            Section("Default Markdown app") {
                Text("To make Galley open every Markdown file: select any .md file in Finder, press ⌘I, choose Galley under “Open with,” then click **Change All**.")
                    .font(.callout)
                Text("macOS doesn't let sandboxed apps change this on your behalf — and Galley wouldn't grab it behind your back anyway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(SettingsKeys.theme) private var themeID = "thesis"
    @AppStorage(SettingsKeys.mode) private var mode = AppearanceMode.system.rawValue
    @AppStorage(SettingsKeys.textScale) private var textScale = 1.0
    @AppStorage(SettingsKeys.measure) private var measure = Measure.normal.rawValue

    @State private var overrides = ThemeOverrides()

    private var theme: GalleyTheme { ThemeStore.theme(id: themeID) }

    private var variant: ThemeStore.Variant {
        switch AppearanceMode(rawValue: mode) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .dark : .light
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(ThemeStore.builtIns) { t in
                    ThemeRow(theme: t, isSelected: t.id == themeID, variant: variant) {
                        themeID = t.id
                    }
                }
                Picker("Mode", selection: $mode) {
                    ForEach(AppearanceMode.allCases) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Type") {
                Picker("Display font", selection: displayFontBinding) {
                    ForEach(FontChoice.allCases) { f in Text(f.label).tag(f) }
                }
                Picker("Body font", selection: bodyFontBinding) {
                    ForEach(FontChoice.allCases) { f in Text(f.label).tag(f) }
                }
                Picker("Mono font", selection: monoFontBinding) {
                    ForEach(FontChoice.allCases) { f in Text(f.label).tag(f) }
                }
                HStack {
                    Text("Heading weight")
                    Slider(value: headingWeightBinding, in: 500...800, step: 20)
                    Text("\(Int(headingWeightBinding.wrappedValue))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                Toggle("Spectral accents", isOn: spectralBinding)
                Slider(value: $textScale, in: 0.8...1.6, step: 0.05) {
                    Text("Text size")
                } minimumValueLabel: {
                    Text("A").font(.caption2)
                } maximumValueLabel: {
                    Text("A").font(.title3)
                }
                Picker("Line width", selection: $measure) {
                    ForEach(Measure.allCases) { m in
                        Text(m.label).tag(m.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Light") {
                ColorPicker("Background", selection: colorBinding(.light, { $0.bg }, { $0.bg = $1 }, { $0.bg }))
                ColorPicker("Text", selection: colorBinding(.light, { $0.ink }, { $0.ink = $1 }, { $0.ink }))
                ColorPicker("Accent", selection: colorBinding(.light, { $0.accent }, { $0.accent = $1 }, { $0.accent }))
            }

            Section("Dark") {
                ColorPicker("Background", selection: colorBinding(.dark, { $0.bg }, { $0.bg = $1 }, { $0.bg }))
                ColorPicker("Text", selection: colorBinding(.dark, { $0.ink }, { $0.ink = $1 }, { $0.ink }))
                ColorPicker("Accent", selection: colorBinding(.dark, { $0.accent }, { $0.accent = $1 }, { $0.accent }))
            }

            Section {
                Button("Reset This Theme") {
                    overrides = ThemeOverrides()
                    ThemeStore.setOverrides(overrides, for: themeID)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
        .onAppear { overrides = ThemeStore.overrides(for: themeID) }
        .onChange(of: themeID) { _, newID in overrides = ThemeStore.overrides(for: newID) }
    }

    private var displayFontBinding: Binding<FontChoice> {
        Binding(
            get: { overrides.displayFont ?? theme.displayFont },
            set: { newValue in
                overrides.displayFont = newValue == theme.displayFont ? nil : newValue
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }

    private var bodyFontBinding: Binding<FontChoice> {
        Binding(
            get: { overrides.bodyFont ?? theme.bodyFont },
            set: { newValue in
                overrides.bodyFont = newValue == theme.bodyFont ? nil : newValue
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }

    private var monoFontBinding: Binding<FontChoice> {
        Binding(
            get: { overrides.monoFont ?? theme.monoFont },
            set: { newValue in
                overrides.monoFont = newValue == theme.monoFont ? nil : newValue
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }

    private var headingWeightBinding: Binding<Double> {
        Binding(
            get: { Double(overrides.headingWeight ?? theme.headingWeight) },
            set: { newValue in
                let intValue = Int(newValue)
                overrides.headingWeight = intValue == theme.headingWeight ? nil : intValue
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }

    private var spectralBinding: Binding<Bool> {
        Binding(
            get: { overrides.spectral ?? theme.spectral },
            set: { newValue in
                overrides.spectral = newValue == theme.spectral ? nil : newValue
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }

    /// Builds a Color binding for one field (bg/ink/accent) of one variant's
    /// PaletteOverride, falling back to the built-in theme's value when unset.
    private func colorBinding(
        _ variant: ThemeStore.Variant,
        _ get: @escaping (PaletteOverride) -> String?,
        _ set: @escaping (inout PaletteOverride, String) -> Void,
        _ defaultHex: @escaping (ThemePalette) -> String
    ) -> Binding<Color> {
        Binding(
            get: {
                let po = variant == .light ? overrides.light : overrides.dark
                let base = variant == .light ? theme.light : theme.dark
                let hex = po.flatMap(get) ?? defaultHex(base)
                return Color(hex: hex) ?? .black
            },
            set: { newColor in
                var po = (variant == .light ? overrides.light : overrides.dark) ?? PaletteOverride()
                set(&po, newColor.toHex())
                if variant == .light { overrides.light = po } else { overrides.dark = po }
                ThemeStore.setOverrides(overrides, for: themeID)
            }
        )
    }
}

private struct PrivacySettings: View {
    @AppStorage(SettingsKeys.allowRemote) private var allowRemote = true
    @State private var folders: [String] = FolderAccessManager.shared.grantedFolders

    var body: some View {
        Form {
            Section {
                Toggle("Load images from the web", isOn: $allowRemote)
                Text("Documents can reference remote images (README badges, screenshots). Turn this off and Galley never touches the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Folders you've granted access to") {
                if folders.isEmpty {
                    Text("None — Galley only reads files you open.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(folders, id: \.self) { path in
                        HStack {
                            Text((path as NSString).abbreviatingWithTildeInPath)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Revoke") {
                                FolderAccessManager.shared.revoke(path: path)
                                folders = FolderAccessManager.shared.grantedFolders
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            Section {
                Text("Galley has no analytics, no accounts, and phones home to no one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 360)
        .onAppear { folders = FolderAccessManager.shared.grantedFolders }
    }
}

private struct AboutSettings: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Galley")
                .font(.title2.weight(.semibold))
            Text("A quiet, beautiful reader for Markdown.")
                .foregroundStyle(.secondary)
            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Divider().padding(.vertical, 4)
            HStack(spacing: 18) {
                Link("Thesis Labs", destination: URL(string: "https://thesis.do")!)
                Link("Source Code", destination: URL(string: "https://github.com/JessieSalas/galley")!)
                Link("Acknowledgements", destination: URL(string: "https://github.com/JessieSalas/galley/blob/main/ACKNOWLEDGEMENTS.md")!)
            }
            .font(.callout)
            Text("Open source under the MIT license.\nSet in Fraunces, Inter, and JetBrains Mono.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
