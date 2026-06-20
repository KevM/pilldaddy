import Foundation
import Observation

/// Single source of truth for reminder preferences, backed by UserDefaults so
/// both views and services read the same values. Not `@MainActor` so it can be a
/// default-initialized stored property of the (nonisolated) `App`/`AppDelegate`;
/// UserDefaults is thread-safe and all mutations happen from the main thread.
@Observable
final class ReminderSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let enabled = "reminders.enabled"
        static let grace = "reminders.graceMinutes"
        static let headsUp = "reminders.headsUpEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.grace: 120,
            Key.headsUp: true,
        ])
    }

    var remindersEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var graceMinutes: Int {
        get { defaults.integer(forKey: Key.grace) }
        set { defaults.set(newValue, forKey: Key.grace) }
    }

    var headsUpEnabled: Bool {
        get { defaults.bool(forKey: Key.headsUp) }
        set { defaults.set(newValue, forKey: Key.headsUp) }
    }
}
