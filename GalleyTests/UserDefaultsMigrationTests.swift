import XCTest
@testable import Galley

final class UserDefaultsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UserDefaultsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testMigratesPaperToLight() {
        defaults.set("paper", forKey: "galley.appearance")
        UserDefaults.registerGalleyDefaults(defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsKeys.mode), AppearanceMode.light.rawValue)
        XCTAssertNil(defaults.object(forKey: "galley.appearance"), "legacy key must be removed after migrating")
    }

    func testMigratesInkToDark() {
        defaults.set("ink", forKey: "galley.appearance")
        UserDefaults.registerGalleyDefaults(defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsKeys.mode), AppearanceMode.dark.rawValue)
        XCTAssertNil(defaults.object(forKey: "galley.appearance"))
    }

    func testSystemLegacyValueNeedsNoTranslation() {
        defaults.set("system", forKey: "galley.appearance")
        UserDefaults.registerGalleyDefaults(defaults)
        // "system" never had an explicit override to begin with — the value
        // read back comes from the registered default, not a migrated one,
        // but it should still resolve to "system" either way.
        XCTAssertEqual(defaults.string(forKey: SettingsKeys.mode), AppearanceMode.system.rawValue)
        XCTAssertNil(defaults.object(forKey: "galley.appearance"))
    }

    func testNoLegacyKeyLeavesRegisteredDefaultInPlace() {
        UserDefaults.registerGalleyDefaults(defaults)
        // No explicit value was ever set — falls through to the registered default.
        XCTAssertEqual(defaults.string(forKey: SettingsKeys.mode), AppearanceMode.system.rawValue)
    }
}
