import SwiftUI

/// First-run explanation, shown once over the Welcome document, before the
/// same system popup Settings already offers (DefaultAppManager). Explain,
/// let the user acknowledge or decline, only then trigger the OS-level
/// confirmation — never silently, never more than once.
struct OnboardingDefaultAppView: View {
    let onFinished: () -> Void

    private enum Stage { case ask, working, done, failed }
    @State private var stage: Stage = .ask

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tint)

            Text("Make Galley your Markdown reader")
                .font(.title3.weight(.semibold))

            Text("Double-clicking a Markdown file anywhere on your Mac will open it in Galley instead of a text editor — this covers every Markdown extension (.md, .markdown, .mdown, .mkdn, .mkd). You can change this anytime in Settings → Reading.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            switch stage {
            case .done:
                Label("Galley is now your default reader", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .failed:
                Text("That didn't take — you can still do it by hand in Settings → Reading.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .ask, .working:
                EmptyView()
            }

            HStack(spacing: 12) {
                Button("Not Now") {
                    onFinished()
                }
                .disabled(stage == .working)

                Button(stage == .working ? "Setting…" : "Set as Default") {
                    stage = .working
                    DefaultAppManager.setGalleyAsDefault { outcome in
                        if case .success = outcome { stage = .done } else { stage = .failed }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            onFinished()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(stage != .ask)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 380)
        .interactiveDismissDisabled(stage == .working)
    }
}
