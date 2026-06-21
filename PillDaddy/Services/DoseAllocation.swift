import Foundation

/// Single source of truth for daily-dose allocation: how many units/day are
/// allocated to routines vs. the prescribed target, plus derived strength totals.
/// All counts are in units (tablets); strength totals are derived (value x count)
/// and only ever within one medication, so no cross-unit conversion is needed.
enum DoseAllocation {
    enum Status { case under, full, over }

    /// Sum of quantity across all the med's routine items, regardless of recurrence.
    static func allocated(_ med: Medication) -> Double {
        (med.routineItems ?? []).reduce(0) { $0 + $1.quantity }
    }

    /// Units/day still unallocated, clamped at zero.
    static func remaining(_ med: Medication) -> Double {
        max(0, med.dailyDoseTarget - allocated(med))
    }

    static let tolerance = 0.0001

    static func isOverTarget(allocated: Double, target: Double) -> Bool {
        allocated > target + tolerance
    }

    static func status(_ med: Medication) -> Status {
        let a = allocated(med)
        if isOverTarget(allocated: a, target: med.dailyDoseTarget) { return .over }
        if a < med.dailyDoseTarget - tolerance { return .under }
        return .full
    }

    /// Derived total strength currently allocated, e.g. 30mg x 2 = 60.
    static func allocatedStrength(_ med: Medication) -> Double {
        med.strengthValue * allocated(med)
    }

    /// Derived total strength at the prescribed target.
    static func targetStrength(_ med: Medication) -> Double {
        med.strengthValue * med.dailyDoseTarget
    }

    /// A scheduled, active med whose allocation does not match its target.
    static func needsAttention(_ med: Medication) -> Bool {
        guard med.isActive, !med.isPRN else { return false }
        return status(med) != .full
    }
}
