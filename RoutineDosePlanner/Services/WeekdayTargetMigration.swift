import Foundation
import SwiftData

/// One-time backfill of per-weekday targets. For meds whose existing schedule is
/// NOT uniform across the week, snapshot the currently-scheduled per-weekday totals
/// into `weekdayDoseTargets` so they keep reporting `.full` under the new day-aware
/// accounting. Uniform daily meds are left as `nil`. Idempotent.
@MainActor
enum WeekdayTargetMigration {
    private static let tolerance = 0.0001

    static func backfill(in context: ModelContext) {
        let userDefaultsKey = "didRunWeekdayTargetBackfill"
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }

        let meds = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        var changed = false
        for med in meds where !med.isPRN && med.weekdayDoseTargets == nil {
            let scheduled = DoseAllocation.scheduledByWeekday(med)
            if scheduled.contains(where: { abs($0 - med.dailyDoseTarget) > tolerance }) {
                med.weekdayDoseTargets = scheduled
                changed = true
            }
        }
        if changed { try? context.save() }

        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }
}
