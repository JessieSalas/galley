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
                Button("Show a Markdown File in Finder…") {
                    NSWorkspace.shared.activateFileViewerSelecting([])
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(SettingsKeys.typeface) private var typeface = Typeface.standard.rawValue
    @AppStorage(SettingsKeys.textScale) private var textScale = 1.0
    @AppStorage(SettingsKeys.measure) private var measure = Measure.normal.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { a in
                        Text(a.label).tag(a.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Paper is warm cream and ink; Ink is a warm near-black. System follows your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Typeface", selection: $typeface) {
                    ForEach(Typeface.allCases) { t in
                        Text(t.label).tag(t.rawValue)
                    }
                }
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
        }
        .formStyle(.grouped)
        .frame(height: 340)
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
                Link("Source Code", destination: URL(string: "https://github.com/thesis-labs/galley")!)
                Link("Acknowledgements", destination: URL(string: "https://github.com/thesis-labs/galley/blob/main/ACKNOWLEDGEMENTS.md")!)
            }
            .font(.callout)
            Text("Open source under the MIT license.\nSet in Bricolage Grotesque, Inter, and JetBrains Mono.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
