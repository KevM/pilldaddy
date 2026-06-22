import Foundation

/// Short label for a routine's recurrence, for inline display next to a routine
/// name. Returns nil for daily routines (no label needed). Variable days are
/// listed comma-separated, e.g. "Thu, Sat".
enum RecurrenceLabel {
    static func short(for routine: Routine) -> String? {
        switch RecurrenceKind(rawValue: routine.recurrenceKind) ?? .daily {
        case .daily:
            return nil
        case .weekdays:
            let days = routine.firingWeekdays
            guard !days.isEmpty else { return nil }
            return days.map { DoseSummaryFormatter.shortWeekdays[$0 - 1] }.joined(separator: ", ")
        }
    }
}
