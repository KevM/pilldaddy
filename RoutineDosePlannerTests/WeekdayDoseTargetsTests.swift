import Testing
@testable import RoutineDosePlanner

struct WeekdayDoseTargetsTests {

    @Test func resolveFallsBackToDailyWhenNil() {
        #expect(WeekdayDoseTargets.resolve(forWeekday: 4, daily: 1.5, perWeekday: nil) == 1.5)
    }

    @Test func resolveUsesPerWeekdayValueWhenSet() {
        let perWeekday = [0, 0, 0, 0, 1, 0, 2.0] // Thu (5) = 1, Sat (7) = 2
        #expect(WeekdayDoseTargets.resolve(forWeekday: 5, daily: 0, perWeekday: perWeekday) == 1)
        #expect(WeekdayDoseTargets.resolve(forWeekday: 7, daily: 0, perWeekday: perWeekday) == 2)
    }

    @Test func expandRepeatsDailyWhenUniform() {
        #expect(WeekdayDoseTargets.expand(daily: 1.5, perWeekday: nil) == Array(repeating: 1.5, count: 7))
    }

    @Test func expandReturnsStoredArrayWhenVariable() {
        let perWeekday = [0, 0, 0, 0, 1, 0, 2.0]
        #expect(WeekdayDoseTargets.expand(daily: 0, perWeekday: perWeekday) == perWeekday)
    }

    @Test func collapseDetectsUniform() {
        let result = WeekdayDoseTargets.collapse(Array(repeating: 1.5, count: 7))
        #expect(result.daily == 1.5)
        #expect(result.perWeekday == nil)
    }

    @Test func collapseKeepsArrayWhenVariable() {
        let values = [0, 0, 0, 0, 1, 0, 2.0]
        let result = WeekdayDoseTargets.collapse(values)
        #expect(result.perWeekday == values)
    }
}
