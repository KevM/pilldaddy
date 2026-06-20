import Foundation
import SwiftData

enum ReminderKind: String, CaseIterable {
    case headsUp, due, followUp
}

/// Plans (and applies) the per-batch notification lifecycle. The `plan` function is
/// pure and unit-tested; `reschedule` is the thin UNUserNotificationCenter layer.
@MainActor
enum ReminderScheduler {

    /// Offsets (minutes after the slot) at which "still due" follow-ups fire.
    static let followUpOffsets = [30, 60, 90]

    struct Planned: Equatable {
        let identifier: String
        let batchUUID: String
        let fireDate: Date
        let kind: ReminderKind
        let title: String
        let body: String
    }

    /// Stable per-slot key used to skip already-logged batches.
    static func slotKey(batchUUID: String, slot: Date) -> String {
        "\(batchUUID)|\(Int(slot.timeIntervalSince1970))"
    }

    /// The notifications to schedule across `horizonDays` starting at `now`'s day.
    /// Pure: no side effects, deterministic for fixed inputs.
    static func plan(
        batches: [Batch],
        now: Date,
        horizonDays: Int,
        graceMinutes: Int,
        headsUpEnabled: Bool,
        masterEnabled: Bool,
        completedSlots: Set<String> = [],
        limit: Int = 64
    ) -> [Planned] {
        guard masterEnabled else { return [] }
        let cal = Calendar.current
        var result: [Planned] = []

        for offset in 0..<max(horizonDays, 0) {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            for batch in batches where DayQuery.recurs(batch, on: day) {
                let medCount = activeMedCount(batch)
                guard medCount > 0 else { continue }
                let slot = DayQuery.slotDate(for: batch, on: day)
                let key = slotKey(batchUUID: batch.uuid.uuidString, slot: slot)
                guard !completedSlots.contains(key) else { continue }

                if headsUpEnabled {
                    result.append(make(batch, slot: slot, kind: .headsUp,
                                       offsetMinutes: -15, medCount: medCount))
                }
                result.append(make(batch, slot: slot, kind: .due,
                                   offsetMinutes: 0, medCount: medCount))
                for m in followUpOffsets where m < graceMinutes {
                    result.append(make(batch, slot: slot, kind: .followUp,
                                       offsetMinutes: m, medCount: medCount))
                }
            }
        }

        return result
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }

    private static func activeMedCount(_ batch: Batch) -> Int {
        (batch.items ?? []).filter {
            ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false)
        }.count
    }

    private static func make(_ batch: Batch, slot: Date, kind: ReminderKind,
                             offsetMinutes: Int, medCount: Int) -> Planned {
        let fire = slot.addingTimeInterval(TimeInterval(offsetMinutes) * 60)
        let meds = "\(medCount) med\(medCount == 1 ? "" : "s")"
        let title: String
        let body: String
        switch kind {
        case .headsUp:
            title = "\(batch.name) coming up"
            body = "\(meds) due in 15 minutes"
        case .due:
            title = "\(batch.name) is due"
            body = "Time for \(meds)"
        case .followUp:
            title = "\(batch.name) still due"
            body = "\(meds) not logged yet"
        }
        let id = "\(batch.uuid.uuidString)|\(Int(slot.timeIntervalSince1970))|\(kind.rawValue)|\(offsetMinutes)"
        return Planned(identifier: id, batchUUID: batch.uuid.uuidString,
                       fireDate: fire, kind: kind, title: title, body: body)
    }
}
