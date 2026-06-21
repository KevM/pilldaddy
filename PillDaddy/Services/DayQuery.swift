import Foundation
import SwiftData

/// Pure read helpers that assemble a single day's logging state from already-fetched
/// model objects. No fetching, so it's reactive in views (driven by `@Query`) and
/// directly unit-testable.
@MainActor
enum DayQuery {

    enum RoutineState { case pending, partial, taken, skipped, missed, completed }

    /// One scheduled med on a day, paired with its existing log (if any).
    struct MedDose: Identifiable {
        let item: RoutineItem
        let log: DoseLog?
        var id: PersistentIdentifier { item.persistentModelID }
    }

    /// A routine occurring on a day, with its active scheduled meds and computed state.
    struct RoutineDay: Identifiable {
        let routine: Routine
        let slotDate: Date
        let meds: [MedDose]
        var id: PersistentIdentifier { routine.persistentModelID }
        var state: RoutineState {
            let loggedCount = meds.filter { $0.log != nil }.count
            if loggedCount == 0 { return .pending }
            if loggedCount < meds.count { return .partial }
            
            let statuses = Set(meds.compactMap { $0.log?.status })
            if statuses == [DoseStatus.taken.rawValue] {
                return .taken
            } else if statuses == [DoseStatus.skipped.rawValue] {
                return .skipped
            } else if statuses == [DoseStatus.missed.rawValue] {
                return .missed
            } else {
                return .completed
            }
        }
        var isCompleted: Bool {
            meds.allSatisfy { $0.log != nil }
        }
    }

    /// A PRN med on a day, with that day's ad-hoc logs (newest first).
    struct PRNDose: Identifiable {
        let med: Medication
        let logs: [DoseLog]
        var id: PersistentIdentifier { med.persistentModelID }
    }

    /// Whether a routine occurs on the given day (daily always; weekdays per its list).
    static func recurs(_ routine: Routine, on day: Date) -> Bool {
        switch RecurrenceKind(rawValue: routine.recurrenceKind) ?? .daily {
        case .daily: return true
        case .weekdays:
            let wd = Calendar.current.component(.weekday, from: day)
            return (routine.weekdays ?? []).contains(wd)
        }
    }

    /// The slot datetime for a routine on a day: that calendar day + the routine's clock time.
    static func slotDate(for routine: Routine, on day: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let comps = cal.dateComponents([.hour, .minute], from: routine.timeOfDay)
        return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0,
                        second: 0, of: start) ?? start
    }

    /// Routines occurring on the day (in time-of-day order), each with active, non-PRN
    /// meds and any existing logs. Empty routines are omitted.
    static func routineDays(from routines: [Routine], on day: Date) -> [RoutineDay] {
        let cal = Calendar.current
        return routines
            .filter { recurs($0, on: day) }
            .compactMap { routine -> RoutineDay? in
                let meds = (routine.items ?? [])
                    .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
                    .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
                    .map { item in
                        MedDose(item: item,
                                log: (item.doseLogs ?? []).first {
                                    cal.isDate($0.scheduledDate, inSameDayAs: day) })
                    }
                guard !meds.isEmpty else { return nil }
                return RoutineDay(routine: routine, slotDate: slotDate(for: routine, on: day), meds: meds)
            }
    }

    /// Active PRN meds, each with that day's logs (newest first).
    static func prnDoses(from meds: [Medication], on day: Date) -> [PRNDose] {
        let cal = Calendar.current
        return meds.map { med in
            let logs = (med.doseLogs ?? [])
                .filter { $0.isPRN && cal.isDate($0.scheduledDate, inSameDayAs: day) }
                .sorted { ($0.takenAt ?? $0.scheduledDate) > ($1.takenAt ?? $1.scheduledDate) }
            return PRNDose(med: med, logs: logs)
        }
    }

    /// Combines a date's calendar components (year/month/day) with a time's clock components (hour/minute/second).
    static func combine(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dateComps = cal.dateComponents([.year, .month, .day], from: date)
        let timeComps = cal.dateComponents([.hour, .minute, .second], from: time)
        var combined = DateComponents()
        combined.year = dateComps.year
        combined.month = dateComps.month
        combined.day = dateComps.day
        combined.hour = timeComps.hour
        combined.minute = timeComps.minute
        combined.second = timeComps.second
        return cal.date(from: combined) ?? date
    }
}
