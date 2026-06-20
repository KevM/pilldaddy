import Foundation
import SwiftData

/// One-time data fixes for dose logs. Idempotent and cheap (single-user dataset).
@MainActor
enum DoseLogMigration {

    /// Sets `isPRN = true` for legacy logs created before the flag existed, where
    /// the absence of a `batchItem` link was the only PRN signal. Idempotent.
    static func backfillPRNFlag(in context: ModelContext) {
        let userDefaultsKey = "didRunDoseLogPRNBackfill"
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }

        let all = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        var changed = false
        for log in all where log.batchItem == nil && !log.isPRN {
            log.isPRN = true
            changed = true
        }
        if changed { try? context.save() }

        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }
}
