import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct DoseAllocationTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    /// A scheduled med built from (recurrence, quantity) routine placements.
    private func med(daily: Double, perWeekday: [Double]? = nil,
                     placements: [(RecurrenceKind, [Int]?, Double)]) -> Medication {
        let m = Medication(name: "Test", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: daily)
        m.weekdayDoseTargets = perWeekday
        context.insert(m)
        for (kind, days, qty) in placements {
            let r = Routine(name: "R", recurrenceKind: kind, weekdays: days)
            context.insert(r)
            context.insert(RoutineItem(quantity: qty, medication: m, routine: r))
        }
        return m
    }

    @Test func scheduledByWeekdayDailyRoutineHitsEveryDay() {
        let m = med(daily: 1, placements: [(.daily, nil, 1.0)])
        #expect(DoseAllocation.scheduledByWeekday(m) == Array(repeating: 1.0, count: 7))
    }

    @Test func scheduledByWeekdayWeekdayRoutineHitsOnlyItsDays() {
        // Thu (5) = 1, Sat (7) = 2
        let m = med(daily: 0, placements: [(.weekdays, [5], 1.0), (.weekdays, [7], 2.0)])
        let s = DoseAllocation.scheduledByWeekday(m)
        #expect(s[4] == 1.0) // Thursday
        #expect(s[6] == 2.0) // Saturday
        #expect(s[0] == 0.0) // Sunday
    }

    @Test func scheduledByWeekdayOverlappingRoutinesSumOnSameDay() {
        // morning daily 1 + evening daily 0.5 => 1.5 every day
        let m = med(daily: 1.5, placements: [(.daily, nil, 1.0), (.daily, nil, 0.5)])
        #expect(DoseAllocation.scheduledByWeekday(m) == Array(repeating: 1.5, count: 7))
    }

    @Test func variableScheduleMatchingTargetsIsFull() {
        // THE MOTIVATING CASE: 1 Thursday, 2 Saturday, targets Thu=1/Sat=2/else=0.
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 2
        let m = med(daily: 0, perWeekday: perWeekday,
                    placements: [(.weekdays, [5], 1.0), (.weekdays, [7], 2.0)])
        #expect(DoseAllocation.status(m) == .full)
    }

    @Test func statusOverWhenAnyDayExceeds() {
        // daily target 1, but a Saturday extra pushes Saturday to 2.
        let m = med(daily: 1, placements: [(.daily, nil, 1.0), (.weekdays, [7], 1.0)])
        #expect(DoseAllocation.status(m) == .over)
    }

    @Test func statusUnderWhenADayIsBelowAndNoneOver() {
        let m = med(daily: 2, placements: [(.daily, nil, 0.5)])
        #expect(DoseAllocation.status(m) == .under)
    }

    @Test func statusFullWhenUniformMatches() {
        let m = med(daily: 1.5, placements: [(.daily, nil, 1.0), (.daily, nil, 0.5)])
        #expect(DoseAllocation.status(m) == .full)
    }

    @Test func remainingAddingToIsMinSlackAcrossRoutineDays() {
        // daily target 2, already 0.5/day scheduled => 1.5 slack on every day.
        let m = med(daily: 2, placements: [(.daily, nil, 0.5)])
        let satRoutine = Routine(name: "Sat", recurrenceKind: .weekdays, weekdays: [7])
        context.insert(satRoutine)
        #expect(DoseAllocation.remaining(m, addingTo: satRoutine) == 1.5)
    }

    @Test func remainingAddingToDailyRoutineConstrainedByTightestDay() {
        // Saturday already full (target 1, scheduled 1); other days have slack.
        var perWeekday = Array(repeating: 2.0, count: 7)
        perWeekday[6] = 1 // Saturday target 1
        let m = med(daily: 2, perWeekday: perWeekday,
                    placements: [(.weekdays, [7], 1.0)])
        let daily = Routine(name: "Daily", recurrenceKind: .daily)
        context.insert(daily)
        // Adding to a daily routine is constrained by Saturday's 0 slack.
        #expect(DoseAllocation.remaining(m, addingTo: daily) == 0)
    }

    @Test func needsAttentionTrueWhenUnderAndScheduled() {
        #expect(DoseAllocation.needsAttention(med(daily: 2, placements: [(.daily, nil, 0.5)])))
    }

    @Test func needsAttentionFalseWhenFull() {
        #expect(!DoseAllocation.needsAttention(med(daily: 1, placements: [(.daily, nil, 1.0)])))
    }

    @Test func needsAttentionFalseForPRN() {
        let m = Medication(name: "PRN", strengthValue: 500, strengthUnit: "mg", dailyDoseTarget: 1, isPRN: true)
        context.insert(m)
        #expect(!DoseAllocation.needsAttention(m))
    }

    @Test func needsAttentionFalseForDiscontinued() {
        let m = med(daily: 2, placements: [(.daily, nil, 0.5)])
        m.isActive = false
        #expect(!DoseAllocation.needsAttention(m))
    }
}
