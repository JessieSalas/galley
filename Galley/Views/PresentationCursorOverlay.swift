import AppKit
import SwiftUI

/// While `active`, replaces the normal arrow over the reading surface with a
/// small filled dot — a presentation should feel like a presentation, not an
/// editor waiting for a click. Purely a cursor: every mouse event passes
/// through untouched, both at the AppKit level (`hitTest` returns nil) and
/// the SwiftUI level (`.allowsHitTesting(false)` at the call site), so
/// scrolling, clicking links, and text selection all work exactly as before.
struct PresentationCursorOverlay: NSViewRepresentable {
    var active: Bool

    func makeNSView(context: Context) -> OverlayView {
        OverlayView()
    }

    func updateNSView(_ nsView: OverlayView, context: Context) {
        nsView.active = active
    }

    final class OverlayView: NSView {
        var active = false {
            didSet {
                guard active != oldValue else { return }
                window?.invalidateCursorRects(for: self)
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // AppKit only auto-invalidates cursor rects on an actual
            // NSWindow-frame resize. A registered addCursorRect(bounds:)
            // otherwise stays frozen at whatever bounds it had when it was
            // registered — it does NOT get re-run just because this
            // subview's own frame changed inside the split view (e.g. the
            // sidebar hiding/showing while presenting). Opt into frame
            // notifications so any bounds change re-invalidates it.
            postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(frameDidChange),
                name: NSView.frameDidChangeNotification,
                object: self
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func frameDidChange() {
            window?.invalidateCursorRects(for: self)
        }

        // Cursor rects are an AppKit mechanism separate from the SwiftUI/
        // responder hit-test chain used for clicks — registering one here
        // doesn't intercept events, only what the cursor looks like.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard active else { return }
            addCursorRect(bounds, cursor: Self.dotCursor)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        private static let dotCursor: NSCursor = {
            let diameter: CGFloat = 14
            let pad: CGFloat = 3
            let size = NSSize(width: diameter + pad * 2, height: diameter + pad * 2)
            let image = NSImage(size: size, flipped: false) { rect in
                let dot = rect.insetBy(dx: pad, dy: pad)
                NSColor.white.withAlphaComponent(0.95).setFill()
                NSBezierPath(ovalIn: dot).fill()
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                NSColor.black.withAlphaComponent(0.55).setStroke()
                ring.stroke()
                return true
            }
            return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
        }()
    }
}
