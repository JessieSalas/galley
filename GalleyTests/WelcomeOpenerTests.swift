import XCTest
@testable import Galley

final class WelcomeOpenerTests: XCTestCase {
    func testNilIsNeverWelcome() {
        XCTAssertFalse(WelcomeOpener.isWelcome(nil))
    }

    func testUnrelatedURLIsNotWelcome() {
        XCTAssertFalse(WelcomeOpener.isWelcome(URL(fileURLWithPath: "/tmp/Notes.md")))
    }

    func testBundledWelcomeURLIsWelcome() throws {
        let url = try XCTUnwrap(WelcomeOpener.url, "Welcome.md must ship in Samples")
        XCTAssertTrue(WelcomeOpener.isWelcome(url))
    }

    func testNonStandardizedPathStillMatches() throws {
        let url = try XCTUnwrap(WelcomeOpener.url)
        // Round-trip through a deliberately non-canonical form (as a
        // document-open callback's URL sometimes arrives), confirming the
        // comparison standardizes both sides instead of relying on exact
        // string equality.
        let messy = url.deletingLastPathComponent()
            .appendingPathComponent(".").appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(WelcomeOpener.isWelcome(messy))
    }
}
