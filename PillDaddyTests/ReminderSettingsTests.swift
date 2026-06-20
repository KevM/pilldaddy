import XCTest
@testable import PillDaddy

@MainActor
final class ReminderSettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaults() {
        let s = ReminderSettings(defaults: freshDefaults())
        XCTAssertTrue(s.remindersEnabled)
        XCTAssertEqual(s.graceMinutes, 120)
        XCTAssertTrue(s.headsUpEnabled)
    }

    func testPersistsChanges() {
        let d = freshDefaults()
        let s = ReminderSettings(defaults: d)
        s.remindersEnabled = false
        s.graceMinutes = 60
        s.headsUpEnabled = false
        let reloaded = ReminderSettings(defaults: d)
        XCTAssertFalse(reloaded.remindersEnabled)
        XCTAssertEqual(reloaded.graceMinutes, 60)
        XCTAssertFalse(reloaded.headsUpEnabled)
    }
}
