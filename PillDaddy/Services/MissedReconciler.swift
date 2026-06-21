import Foundation
import SwiftData

/// Sweeps past batch slots whose grace window has elapsed and materializes `missed`
/// DoseLogs for any med that was never logged. Runs on app launch/foreground.
@MainActor
enum MissedReconciler {

    static func reconcile(
        batches: [Routine],
        now: Date,
        graceMinutes: Int,
        lookbackDays: Int = 7,
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let grace = TimeInterval(graceMinutes) * 60
        for offset in 0...max(lookbackDays, 0) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            for bd in DayQuery.batchDays(from: batches, on: day) {
                let cutoff = bd.slotDate.addingTimeInterval(grace)
                guard now >= cutoff else { continue }
                for med in bd.meds where med.log == nil {
                    DoseLogService.materializeMissed(med.item, on: day, in: context)
                }
            }
        }
    }
}
