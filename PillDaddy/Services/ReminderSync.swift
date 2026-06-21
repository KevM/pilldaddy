import Foundation
import SwiftData

/// Single entry point for re-syncing notifications + the Live Activity to current
/// state. Called on foreground, after logging, and on settings changes.
@MainActor
enum ReminderSync {
    static let horizonDays = 3

    static func refresh(context: ModelContext, settings: ReminderSettings, now: Date = .now) {
        let batches = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        let completed = ReminderScheduler.completedSlotKeys(
            batches: batches, now: now, horizonDays: horizonDays)
        ReminderScheduler.reschedule(
            batches: batches, settings: settings, now: now,
            horizonDays: horizonDays, completedSlots: completed)
        LiveActivityController.refresh(
            batches: batches, now: now, graceMinutes: settings.graceMinutes,
            enabled: settings.remindersEnabled)
    }
}
