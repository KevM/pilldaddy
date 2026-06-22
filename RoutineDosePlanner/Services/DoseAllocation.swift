import Foundation

/// Single source of truth for daily-dose allocation: how many units/day are
/// allocated to routines vs. the prescribed target, plus derived strength totals.
/// All counts are in units (tablets); strength totals are derived (value x count)
/// and only ever within one medication, so no cross-unit conversion is needed.
enum DoseAllocation {
    enum Status { case under, full, over }


    static let tolerance = 0.0001

    static func isOverTarget(allocated: Double, target: Double) -> Bool {
        allocated > target + tolerance
    }

    /// Total units scheduled on each Calendar weekday (1=Sun…7=Sat). Index = weekday-1.
    static func scheduledByWeekday(_ med: Medication) -> [Double] {
        var totals = [Double](repeating: 0, count: 7)
        for item in med.routineItems ?? [] {
            guard let routine = item.routine else { continue }
            for wd in routine.firingWeekdays { totals[wd - 1] += item.quantity }
        }
        return totals
    }

    static func status(_ med: Medication) -> Status {
        let scheduled = scheduledByWeekday(med)
        var anyUnder = false
        for wd in 1...7 {
            let target = med.target(forWeekday: wd)
            if isOverTarget(allocated: scheduled[wd - 1], target: target) { return .over }
            if scheduled[wd - 1] < target - tolerance { anyUnder = true }
        }
        return anyUnder ? .under : .full
    }

    /// Max additional quantity addable to `routine` without pushing any of its
    /// firing days over target — the minimum slack across those days.
    static func remaining(_ med: Medication, addingTo routine: Routine) -> Double {
        let scheduled = scheduledByWeekday(med)
        return routine.firingWeekdays
            .map { max(0, med.target(forWeekday: $0) - scheduled[$0 - 1]) }
            .min() ?? 0
    }

    /// True if adding `quantity` to `routine` would push any firing day over target.
    static func adding(_ quantity: Double, to routine: Routine, exceedsTargetFor med: Medication) -> Bool {
        quantity > remaining(med, addingTo: routine) + tolerance
    }

    /// True if any weekday's total across `placements` exceeds the resolved target
    /// for that day. Used to validate prospective add/change before persisting.
    static func placementsOverTarget(
        daily: Double, perWeekday: [Double]?,
        placements: [(routine: Routine, quantity: Double)]
    ) -> Bool {
        var totals = [Double](repeating: 0, count: 7)
        for p in placements {
            for wd in p.routine.firingWeekdays { totals[wd - 1] += p.quantity }
        }
        for wd in 1...7 {
            let target = WeekdayDoseTargets.resolve(forWeekday: wd, daily: daily, perWeekday: perWeekday)
            if isOverTarget(allocated: totals[wd - 1], target: target) { return true }
        }
        return false
    }

    /// True if moving `item` to `routine` would push any of the destination's days
    /// over target. Relocation changes which days the quantity lands on.
    static func moving(_ item: RoutineItem, to routine: Routine) -> Bool {
        guard let med = item.medication, let from = item.routine else { return false }
        var totals = scheduledByWeekday(med)
        for wd in from.firingWeekdays { totals[wd - 1] -= item.quantity }
        for wd in routine.firingWeekdays { totals[wd - 1] += item.quantity }
        for wd in 1...7 where isOverTarget(allocated: totals[wd - 1], target: med.target(forWeekday: wd)) {
            return true
        }
        return false
    }


    /// A scheduled, active med whose allocation does not match its target.
    static func needsAttention(_ med: Medication) -> Bool {
        guard med.isActive, !med.isPRN else { return false }
        return status(med) != .full
    }
}
