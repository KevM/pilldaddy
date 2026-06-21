import Foundation
import Testing
@testable import RoutineDosePlanner

@MainActor
struct ReminderSettingsTests {

    private func freshDefaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test
    func testDefaults() {
        let s = ReminderSettings(defaults: freshDefaults())
        #expect(s.remindersEnabled)
        #expect(s.graceMinutes == 120)
        #expect(s.headsUpEnabled)
    }

    @Test
    func testPersistsChanges() {
        let d = freshDefaults()
        let s = ReminderSettings(defaults: d)
        s.remindersEnabled = false
        s.graceMinutes = 60
        s.headsUpEnabled = false
        let reloaded = ReminderSettings(defaults: d)
        #expect(!reloaded.remindersEnabled)
        #expect(reloaded.graceMinutes == 60)
        #expect(!reloaded.headsUpEnabled)
    }
}

