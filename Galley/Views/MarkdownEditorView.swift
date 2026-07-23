import SwiftUI
import AppKit
import Combine

/// Plain-text NSTextView wrapped for SwiftUI. Full-function source editing —
/// undo, spell check, the system find bar — with none of the smart-quote /
/// text-replacement autocorrections that would mangle Markdown.
struct MarkdownEditorView: NSViewRepresentable {
    @ObservedObject var model: ReaderModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 32, height: 28)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true

        context.coordinator.textView = textView
        textView.string = model.draftText
        context.coordinator.applyTypography()
        context.coordinator.highlight()
        context.coordinator.observeThemeChanges()
        model.editorTextView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        guard textView.string != model.draftText else { return }
        // The model changed underneath us (disk adopt, discard, initial
        // load) — push the new text in, preserving selection if it's still
        // in bounds so the cursor doesn't jump on unrelated updates.
        let previousSelection = textView.selectedRanges
        textView.string = model.draftText
        let newLength = (textView.string as NSString).length
        if previousSelection.allSatisfy({ NSMaxRange($0.rangeValue) <= newLength }) {
            textView.selectedRanges = previousSelection
        }
        context.coordinator.highlight()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.model?.editorTextView = nil
    }

    /// FontChoice → NSFont for the editor. Fraunces/Bricolage/Inter aren't
    /// installed system-wide, so the editor only honors mono and serif
    /// choices and falls back to the system font for everything else —
    /// source editing is mono territory regardless of the document's body font.
    static func nsFont(for choice: FontChoice, size: CGFloat) -> NSFont {
        switch choice {
        case .jetbrainsMono, .sfMono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .newYork:
            let descriptor = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body).withDesign(.serif)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        case .fraunces, .bricolage, .inter, .system:
            return NSFont.systemFont(ofSize: size)
        }
    }

    /// Mirrors ReaderModel's private `effectiveMode()` — resolves "system"
    /// against the app's current effective appearance.
    static func effectiveVariant() -> ThemeStore.Variant {
        let pref = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.mode) ?? "") ?? .system
        switch pref {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .dark : .light
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var model: ReaderModel?
        weak var textView: NSTextView?
        private var highlightWork: DispatchWorkItem?
        private var defaultsObserver: AnyCancellable?

        /// The editor keeps its OWN undo stack. Falling through to the
        /// window's undo manager would register edits with NSDocument, which
        /// marks the (read-only) document dirty and triggers doomed autosave
        /// attempts — the "document could not be autosaved" complaint.
        let editorUndoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? {
            editorUndoManager
        }

        init(model: ReaderModel) {
            self.model = model
        }

        /// Re-fonts and re-highlights when the theme, mode, or text size
        /// changes — any of which lands as a plain UserDefaults write.
        func observeThemeChanges() {
            defaultsObserver = NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification)
                .debounce(for: .seconds(0.15), scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.applyTypography()
                    self?.highlight()
                }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let text = textView.string
            Task { @MainActor [weak model] in
                model?.draftText = text
            }
            scheduleHighlight()
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.highlight() }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }
            let resolved = currentResolvedTheme()
            let font = MarkdownEditorView.nsFont(for: resolved.monoFont, size: currentFontSize())
            MarkdownSourceHighlighter.highlight(storage, palette: resolved.palette, baseFont: font)
        }

        func applyTypography() {
            guard let textView else { return }
            let resolved = currentResolvedTheme()
            let font = MarkdownEditorView.nsFont(for: resolved.monoFont, size: currentFontSize())
            let bg = NSColor(hex: resolved.palette.bg) ?? .textBackgroundColor
            let ink = NSColor(hex: resolved.palette.ink) ?? .textColor
            let accent = NSColor(hex: resolved.palette.accent) ?? .controlAccentColor

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.5

            textView.font = font
            textView.textColor = ink
            textView.backgroundColor = bg
            textView.insertionPointColor = accent
            textView.enclosingScrollView?.backgroundColor = bg
            textView.selectedTextAttributes = [.backgroundColor: accent.withAlphaComponent(0.25)]
            textView.defaultParagraphStyle = paragraphStyle
            textView.typingAttributes = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraphStyle]

            if let storage = textView.textStorage, storage.length > 0 {
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: storage.length))
            }
        }

        private func currentResolvedTheme() -> ResolvedTheme {
            ThemeStore.resolved(theme: ThemeStore.current(), variant: MarkdownEditorView.effectiveVariant())
        }

        private func currentFontSize() -> CGFloat {
            let scale = UserDefaults.standard.double(forKey: SettingsKeys.textScale)
            return 13.5 * (scale > 0 ? scale : 1.0)
        }
    }
}

extension NSTextView {
    /// `performTextFinderAction(_:)` reads the sender's `tag` to know which
    /// find command to run — build a throwaway control instead of routing
    /// through an actual menu item click.
    func performFindAction(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }
}
