import Foundation
import SwiftData

/// Pure read helpers that assemble a single day's logging state from already-fetched
/// model objects. No fetching, so it's reactive in views (driven by `@Query`) and
/// directly unit-testable.
@MainActor
enum DayQuery {

    enum BatchState { case pending, partial, taken }

    /// One scheduled med on a day, paired with its existing log (if any).
    struct MedDose: Identifiable {
        let item: BatchItem
        let log: DoseLog?
        var id: PersistentIdentifier { item.persistentModelID }
    }

    /// A batch occurring on a day, with its active scheduled meds and computed state.
    struct BatchDay: Identifiable {
        let batch: Batch
        let slotDate: Date
        let meds: [MedDose]
        var id: PersistentIdentifier { batch.persistentModelID }
        var state: BatchState {
            let logged = meds.filter { $0.log != nil }.count
            if logged == 0 { return .pending }
            return logged == meds.count ? .taken : .partial
        }
    }

    /// A PRN med on a day, with that day's ad-hoc logs (newest first).
    struct PRNDose: Identifiable {
        let med: Medication
        let logs: [DoseLog]
        var id: PersistentIdentifier { med.persistentModelID }
    }

    /// Whether a batch occurs on the given day (daily always; weekdays per its list).
    static func recurs(_ batch: Batch, on day: Date) -> Bool {
        switch RecurrenceKind(rawValue: batch.recurrenceKind) ?? .daily {
        case .daily: return true
        case .weekdays:
            let wd = Calendar.current.component(.weekday, from: day)
            return (batch.weekdays ?? []).contains(wd)
        }
    }

    /// The slot datetime for a batch on a day: that calendar day + the batch's clock time.
    static func slotDate(for batch: Batch, on day: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let comps = cal.dateComponents([.hour, .minute], from: batch.timeOfDay)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                        second: 0, of: start) ?? start
    }

    /// Batches occurring on the day (in their stored order), each with active, non-PRN
    /// meds and any existing logs. Empty batches are omitted.
    static func batchDays(from batches: [Batch], on day: Date) -> [BatchDay] {
        let cal = Calendar.current
        return batches
            .filter { recurs($0, on: day) }
            .compactMap { batch -> BatchDay? in
                let meds = (batch.items ?? [])
                    .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
                    .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
                    .map { item in
                        MedDose(item: item,
                                log: (item.doseLogs ?? []).first {
                                    cal.isDate($0.scheduledDate, inSameDayAs: day) })
                    }
                guard !meds.isEmpty else { return nil }
                return BatchDay(batch: batch, slotDate: slotDate(for: batch, on: day), meds: meds)
            }
    }

    /// Active PRN meds, each with that day's logs (newest first).
    static func prnDoses(from meds: [Medication], on day: Date) -> [PRNDose] {
        let cal = Calendar.current
        return meds.map { med in
            let logs = (med.doseLogs ?? [])
                .filter { $0.batchItem == nil && cal.isDate($0.scheduledDate, inSameDayAs: day) }
                .sorted { ($0.takenAt ?? $0.scheduledDate) > ($1.takenAt ?? $1.scheduledDate) }
            return PRNDose(med: med, logs: logs)
        }
    }
}
