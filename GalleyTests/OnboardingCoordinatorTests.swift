import XCTest
@testable import Galley

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    /// Explicitly "Galley is not yet the default" — the state these tests
    /// mean to exercise. Left implicit, it resolved to the real
    /// LaunchServices registration and the suite passed or failed depending
    /// on the machine.
    private func makeCoordinator(alreadyDefault: Bool = false) -> OnboardingCoordinator {
        OnboardingCoordinator(defaults: defaults, isAlreadyDefault: { alreadyDefault })
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPresentsOnFirstCall() {
        let coordinator = makeCoordinator()
        let windowA = UUID()
        XCTAssertFalse(coordinator.isPresenting(owner: windowA))

        coordinator.presentIfNeeded(owner: windowA)

        XCTAssertTrue(coordinator.isPresenting(owner: windowA))
    }

    func testNeverAsksTwice() {
        let coordinator = makeCoordinator()
        let windowA = UUID()
        coordinator.presentIfNeeded(owner: windowA)
        coordinator.dismiss(owner: windowA)
        XCTAssertFalse(coordinator.isPresenting(owner: windowA))

        let windowB = UUID()
        coordinator.presentIfNeeded(owner: windowB)

        XCTAssertFalse(coordinator.isPresenting(owner: windowB), "must not re-prompt once dismissed")
    }

    func testDismissPersistsAcrossInstances() {
        let priorSession = makeCoordinator()
        let priorWindow = UUID()
        priorSession.presentIfNeeded(owner: priorWindow)
        priorSession.dismiss(owner: priorWindow)

        // A fresh coordinator instance (e.g. a later launch) reading the
        // same defaults suite must still honor the "already asked" flag.
        let relaunched = makeCoordinator()
        let window = UUID()
        relaunched.presentIfNeeded(owner: window)

        XCTAssertFalse(relaunched.isPresenting(owner: window))
    }

    func testOnlyOneWindowEverClaimsThePrompt() {
        let coordinator = makeCoordinator()
        let windowA = UUID()
        let windowB = UUID()

        coordinator.presentIfNeeded(owner: windowA)
        coordinator.presentIfNeeded(owner: windowB)

        XCTAssertTrue(coordinator.isPresenting(owner: windowA), "the first window to claim it should keep it")
        XCTAssertFalse(coordinator.isPresenting(owner: windowB), "a second window must not also present it")
    }

    func testDismissingFromANonOwningWindowIsANoOp() {
        let coordinator = makeCoordinator()
        let windowA = UUID()
        let windowB = UUID()
        coordinator.presentIfNeeded(owner: windowA)

        coordinator.dismiss(owner: windowB)

        XCTAssertTrue(coordinator.isPresenting(owner: windowA), "window B dismissing must not affect window A's sheet")
    }

    func testReleaseIfOwnerFreesTheClaimForALaterWindow() {
        let coordinator = makeCoordinator()
        let windowA = UUID()
        coordinator.presentIfNeeded(owner: windowA)

        // Window A closed without the user making a choice.
        coordinator.releaseIfOwner(windowA)

        let windowB = UUID()
        coordinator.presentIfNeeded(owner: windowB)
        XCTAssertTrue(coordinator.isPresenting(owner: windowB), "closing the owning window must not lock out later windows")
    }

    func testReleaseIfOwnerIgnoresANonOwningWindow() {
        let coordinator = makeCoordinator()
        let windowA = UUID()
        coordinator.presentIfNeeded(owner: windowA)

        coordinator.releaseIfOwner(UUID())

        XCTAssertTrue(coordinator.isPresenting(owner: windowA), "releasing a different owner must not affect the real owner")
    }

    /// The branch that broke the build: someone who already set Galley as
    /// their default reader must never see the prompt, and must not be
    /// asked again later either.
    func testNeverPromptsSomeoneWhoIsAlreadyDefault() {
        let coordinator = makeCoordinator(alreadyDefault: true)
        let window = UUID()

        coordinator.presentIfNeeded(owner: window)

        XCTAssertFalse(coordinator.isPresenting(owner: window), "must not nag an existing default")

        let later = makeCoordinator()
        let laterWindow = UUID()
        later.presentIfNeeded(owner: laterWindow)
        XCTAssertFalse(later.isPresenting(owner: laterWindow), "being default already counts as asked")
    }
}
