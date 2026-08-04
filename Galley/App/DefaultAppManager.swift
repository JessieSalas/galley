import AppKit
import UniformTypeIdentifiers

/// Makes Galley the default Markdown reader, for every Markdown extension
/// rather than just `.md`.
///
/// Two things make this harder than one `setDefaultApplication` call:
///
/// 1. Markdown has no single UTI. `.md` and `.markdown` resolve to
///    `net.daringfireball.markdown`, but the long tail (`.mkd`, `.mdx`,
///    `.qmd`, …) resolves to a *dynamic* UTI on a stock Mac, because nothing
///    registers a type for them. `setDefaultApplication` against a dynamic
///    UTI reports no error and changes nothing, so Galley exports
///    `do.thesis.galley.markdown` (see Info.plist) to make those real types.
/// 2. The API reports success for work it did not do. Trusting `error == nil`
///    is what let someone finish the whole "set as default" flow, see a
///    success state, and still have their files open elsewhere. Every set is
///    now read back before it is called a success.
enum DefaultAppManager {
    /// Every type Galley wants to own, in the order a person would care about.
    static var markdownTypes: [UTType] {
        var types: [UTType] = [.markdownDoc]
        if let extended = UTType("do.thesis.galley.markdown") {
            types.append(extended)
        }
        // Anything still resolving to a dynamic type can't be bound, but
        // include real ones a future macOS (or another app) may register.
        for ext in ["mdown", "mkdn", "mkd", "mdwn", "mdtxt", "mdtext", "markdn", "mdx", "qmd", "rmd"] {
            guard let type = UTType(filenameExtension: ext), !type.isDynamic else { continue }
            if !types.contains(type) { types.append(type) }
        }
        return types
    }

    /// Result of trying to become the default reader. `.partial` matters:
    /// LaunchServices can take one type and refuse another, and saying
    /// "done" in that case is the bug this type exists to prevent.
    enum Outcome {
        case success
        case partial(bound: [UTType], unbound: [UTType])
        case failure
    }

    /// Sets each type in turn, never in parallel.
    ///
    /// macOS puts a system confirmation dialog (CoreServicesUIAgent) in front
    /// of every default-app change, and the completion handler does not fire
    /// until it is answered. Firing all the calls at once therefore stacks one
    /// dialog per type on top of each other, which reads as a broken app and
    /// leaves most types unbound when someone dismisses the pile. One at a
    /// time means one prompt, answered, before the next is asked for.
    static func setGalleyAsDefault(completion: @escaping (Outcome) -> Void) {
        // The dialog belongs to the system, not to us; if Galley isn't
        // frontmost it can appear behind whatever is, which is a good way for
        // someone to never see the prompt they are waiting on.
        NSApp.activate(ignoringOtherApps: true)
        // Only ask for what isn't already ours. macOS raises one prompt per
        // change, so skipping the settled types is the difference between one
        // dialog and a stack of them — and makes a second run, or a run by
        // someone who already set `.md` by hand, silent instead of noisy.
        setSequentially(markdownTypes.filter { !isDefault(for: $0) }, completion: completion)
    }

    private static func setSequentially(_ remaining: [UTType], completion: @escaping (Outcome) -> Void) {
        guard let type = remaining.first else {
            // LaunchServices updates its database asynchronously, so an
            // immediate read can still report the old handler.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let all = markdownTypes
                let bound = all.filter { isDefault(for: $0) }
                let unbound = all.filter { !isDefault(for: $0) }
                if unbound.isEmpty {
                    completion(.success)
                } else if bound.isEmpty {
                    completion(.failure)
                } else {
                    completion(.partial(bound: bound, unbound: unbound))
                }
            }
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { _ in
            // The error is deliberately ignored: it comes back nil for changes
            // that did not happen. The read-back above is the real check.
            DispatchQueue.main.async {
                setSequentially(Array(remaining.dropFirst()), completion: completion)
            }
        }
    }

    static func isDefault(for type: UTType) -> Bool {
        guard let registered = NSWorkspace.shared.urlForApplication(toOpen: type) else { return false }
        return registered.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Whether Galley owns the primary Markdown type — used to skip the
    /// first-run prompt. Standardized on both sides, same as
    /// WelcomeOpener.isWelcome: these URLs come from different APIs
    /// (Launch Services vs. the running bundle) and plain `==` doesn't
    /// tolerate the path differences that can appear between them.
    static var isGalleyDefault: Bool {
        isDefault(for: .markdownDoc)
    }
}
