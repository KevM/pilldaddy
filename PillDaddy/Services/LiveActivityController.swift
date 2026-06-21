import Foundation
import SwiftData
import ActivityKit

/// Manages a single Live Activity for the most urgent due/overdue batch today.
/// Local-only: starts/updates only while the app is foregrounded (no push).
@MainActor
enum LiveActivityController {

    /// Reconciles the running activity with the current state. Ends it when no batch
    /// is in its pester window, or starts/updates it for the focus batch.
    static func refresh(batches: [Batch], now: Date, graceMinutes: Int, enabled: Bool) {
        let running = Activity<PillReminderAttributes>.activities

        guard enabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll(running)
            return
        }

        let grace = TimeInterval(graceMinutes) * 60
        guard let focus = focusBatch(batches: batches, now: now, grace: grace) else {
            endAll(running)
            return
        }

        let slot = DayQuery.slotDate(for: focus, on: now)
        let graceEnd = slot.addingTimeInterval(grace)
        let tier = ReminderTier.forElapsed(now.timeIntervalSince(slot), grace: grace)
        let state = PillReminderAttributes.ContentState(
            scheduledDate: slot, graceEndDate: graceEnd, tier: tier)
        let content = ActivityContent(state: state, staleDate: graceEnd)

        if let existing = running.first(where: { $0.attributes.batchID == focus.uuid.uuidString }) {
            Task { await existing.update(content) }
            // end any other stale activities
            for a in running where a.attributes.batchID != focus.uuid.uuidString {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        } else {
            endAll(running)
            let attributes = PillReminderAttributes(
                batchID: focus.uuid.uuidString, batchName: focus.name,
                colorHex: focus.colorHex, medCount: activeMedCount(focus))
            _ = try? Activity.request(attributes: attributes, content: content)
        }
    }

    /// Earliest batch today whose slot is in the pester window [slot, slot+grace)
    /// and is not fully logged.
    private static func focusBatch(batches: [Batch], now: Date, grace: TimeInterval) -> Batch? {
        DayQuery.batchDays(from: batches, on: now)
            .filter { !$0.isCompleted }
            .filter { now >= $0.slotDate && now < $0.slotDate.addingTimeInterval(grace) }
            .min { $0.slotDate < $1.slotDate }?
            .batch
    }

    private static func activeMedCount(_ batch: Batch) -> Int {
        (batch.items ?? []).filter {
            ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false)
        }.count
    }

    private static func endAll(_ running: [Activity<PillReminderAttributes>]) {
        for a in running { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
