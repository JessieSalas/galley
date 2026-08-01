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

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testPresentsOnFirstCall() {
        let coordinator = OnboardingCoordinator(defaults: defaults)
        let windowA = UUID()
        XCTAssertFalse(coordinator.isPresenting(owner: windowA))

        coordinator.presentIfNeeded(owner: windowA)

        // Galley is never the registered default handler in a test runner,
        // so the only gate left is "have we ever asked" — which is false.
        XCTAssertTrue(coordinator.isPresenting(owner: windowA))
    }

    func testNeverAsksTwice() {
        let coordinator = OnboardingCoordinator(defaults: defaults)
        let windowA = UUID()
        coordinator.presentIfNeeded(owner: windowA)
        coordinator.dismiss(owner: windowA)
        XCTAssertFalse(coordinator.isPresenting(owner: windowA))

        let windowB = UUID()
        coordinator.presentIfNeeded(owner: windowB)

        XCTAssertFalse(coordinator.isPresenting(owner: windowB), "must not re-prompt once dismissed")
    }

    func testDismissPersistsAcrossInstances() {
        let priorSession = OnboardingCoordinator(defaults: defaults)
        let priorWindow = UUID()
        priorSession.presentIfNeeded(owner: priorWindow)
        priorSession.dismiss(owner: priorWindow)

        // A fresh coordinator instance (e.g. a later launch) reading the
        // same defaults suite must still honor the "already asked" flag.
        let relaunched = OnboardingCoordinator(defaults: defaults)
        let window = UUID()
        relaunched.presentIfNeeded(owner: window)

        XCTAssertFalse(relaunched.isPresenting(owner: window))
    }

    func testOnlyOneWindowEverClaimsThePrompt() {
        let coordinator = OnboardingCoordinator(defaults: defaults)
        let windowA = UUID()
        let windowB = UUID()

        coordinator.presentIfNeeded(owner: windowA)
        coordinator.presentIfNeeded(owner: windowB)

        XCTAssertTrue(coordinator.isPresenting(owner: windowA), "the first window to claim it should keep it")
        XCTAssertFalse(coordinator.isPresenting(owner: windowB), "a second window must not also present it")
    }

    func testDismissingFromANonOwningWindowIsANoOp() {
        let coordinator = OnboardingCoordinator(defaults: defaults)
        let windowA = UUID()
        let windowB = UUID()
        coordinator.presentIfNeeded(owner: windowA)

        coordinator.dismiss(owner: windowB)

        XCTAssertTrue(coordinator.isPresenting(owner: windowA), "window B dismissing must not affect window A's sheet")
    }

    func testReleaseIfOwnerFreesTheClaimForALaterWindow() {
        let coordinator = OnboardingCoordinator(defaults: defaults)
        let windowA = UUID()
        coordinator.presentIfNeeded(owner: windowA)

        // Window A closed without the user making a choice.
        coordinator.releaseIfOwner(windowA)

        let windowB = UUID()
        coordinator.presentIfNeeded(owner: windowB)
        XCTAssertTrue(coordinator.isPresenting(owner: windowB), "closing the owning window must not lock out later windows")
    }

    func testReleaseIfOwnerIgnoresANonOwningWindow() {
        let coordinator = OnboardingCoordinator(defaults: defaults)
        let windowA = UUID()
        coordinator.presentIfNeeded(owner: windowA)

        coordinator.releaseIfOwner(UUID())

        XCTAssertTrue(coordinator.isPresenting(owner: windowA), "releasing a different owner must not affect the real owner")
    }
}
