import Testing
@testable import RoutineDosePlanner

struct RoutineFiringWeekdaysTests {

    @Test func dailyRoutineFiresEveryWeekday() {
        let routine = Routine(name: "Daily", recurrenceKind: .daily)
        #expect(routine.firingWeekdays == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func weekdayRoutineFiresOnlyItsDaysSorted() {
        let routine = Routine(name: "Thu/Sat", recurrenceKind: .weekdays, weekdays: [7, 5])
        #expect(routine.firingWeekdays == [5, 7])
    }

    @Test func weekdayRoutineWithNoDaysFiresNothing() {
        let routine = Routine(name: "Empty", recurrenceKind: .weekdays, weekdays: nil)
        #expect(routine.firingWeekdays == [])
    }
}
