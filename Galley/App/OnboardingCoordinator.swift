import AppKit

/// Presents the "set Galley as your default Markdown reader" explanation
/// exactly once, on the very first Welcome document a fresh install shows —
/// never on later launches, and never if the user already set it from
/// Settings. Mirrors ActiveModelTracker's cross-scene singleton pattern
/// (GalleyCommands.swift), since SwiftUI Commands/Views have no shared owner.
///
/// A bare `Bool` isn't enough here: every open DocumentView observes this one
/// instance, so a flag with no owner would present the sheet in every open
/// window at once, and dismissing it in one window would yank it out from
/// under every other window too. `presentingOwner` tracks exactly which
/// window claimed the prompt; every other window's sheet binding simply
/// never becomes true.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    static let shared = OnboardingCoordinator()

    @Published private(set) var presentingOwner: UUID?

    /// True while any window is showing the prompt — used to keep a window
    /// from queuing a second sheet (Export/Print) on top of it.
    var isPresentingAnywhere: Bool { presentingOwner != nil }

    private let hasPromptedKey = "galley.hasPromptedDefaultApp"
    private let defaults: UserDefaults
    /// Injected rather than read straight from DefaultAppManager so the
    /// prompt logic is testable. Reading the real LaunchServices
    /// registration made the tests depend on how the machine running them
    /// happens to be configured: once Galley actually was the default
    /// Markdown reader, five of them started failing and blocked a release.
    private let isAlreadyDefault: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        isAlreadyDefault: @escaping () -> Bool = { DefaultAppManager.isGalleyDefault }
    ) {
        self.defaults = defaults
        self.isAlreadyDefault = isAlreadyDefault
    }

    func presentIfNeeded(owner: UUID) {
        guard presentingOwner == nil else { return }
        guard !defaults.bool(forKey: hasPromptedKey) else { return }
        // Don't nag someone who already set this from Settings themselves.
        guard !isAlreadyDefault() else {
            defaults.set(true, forKey: hasPromptedKey)
            return
        }
        presentingOwner = owner
    }

    func isPresenting(owner: UUID) -> Bool {
        presentingOwner == owner
    }

    /// Called by either button in the sheet — asked once, ever.
    func dismiss(owner: UUID) {
        guard presentingOwner == owner else { return }
        defaults.set(true, forKey: hasPromptedKey)
        presentingOwner = nil
    }

    /// The owning window closed without the user making a choice — release
    /// the claim so a later Welcome window isn't locked out forever.
    func releaseIfOwner(_ owner: UUID) {
        if presentingOwner == owner { presentingOwner = nil }
    }
}
