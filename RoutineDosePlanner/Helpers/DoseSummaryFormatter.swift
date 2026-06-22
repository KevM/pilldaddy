import Foundation

/// Builds human-readable dose strings for the medication detail view. Pure and
/// unit-testable; weekday names come from a fixed short-symbol list (1=Sun…7=Sat).
enum DoseSummaryFormatter {
    static let shortWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The prescribed target. Uniform → "1.5 tablet/day · 45 mg/day".
    /// Variable → "Thu 1 · Sat 2 · 3 tablet/wk".
    static func summary(for med: Medication) -> String {
        let form = med.form
        if let perWeekday = med.weekdayDoseTargets {
            let parts = (1...7).compactMap { wd -> String? in
                let qty = perWeekday[wd - 1]
                guard qty > 0 else { return nil }
                return "\(shortWeekdays[wd - 1]) \(DoseFormat.qty(qty))"
            }
            let weekly = perWeekday.reduce(0, +)
            return (parts + ["\(DoseFormat.qty(weekly)) \(form)/wk"]).joined(separator: " · ")
        } else {
            let perDayStrength = med.dailyDoseTarget * med.strengthValue
            return "\(DoseFormat.qty(med.dailyDoseTarget)) \(form)/day · \(DoseFormat.qty(perDayStrength)) \(med.strengthUnit)/day"
        }
    }

    /// Description of the under/over mismatch, or nil when full. Names the worst
    /// offending day for variable schedules.
    static func mismatch(for med: Medication) -> String? {
        guard DoseAllocation.status(med) != .full else { return nil }
        let scheduled = DoseAllocation.scheduledByWeekday(med)
        // Prefer an over day; else the first under day.
        for wd in 1...7 where scheduled[wd - 1] > med.target(forWeekday: wd) + 0.0001 {
            return dayMismatch(wd, scheduled: scheduled[wd - 1], target: med.target(forWeekday: wd), form: med.form)
        }
        for wd in 1...7 where scheduled[wd - 1] < med.target(forWeekday: wd) - 0.0001 {
            return dayMismatch(wd, scheduled: scheduled[wd - 1], target: med.target(forWeekday: wd), form: med.form)
        }
        return nil
    }

    private static func dayMismatch(_ wd: Int, scheduled: Double, target: Double, form: String) -> String {
        "\(shortWeekdays[wd - 1]): \(DoseFormat.qty(scheduled)) of \(DoseFormat.qty(target)) \(form)"
    }
}
