import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct ReminderSchedulerTests {

    private let container: ModelContainer
    private let context: ModelContext
    private var cal: Calendar { Calendar.current }

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    /// A daily routine at the given clock time with one active scheduled med.
    private func makeRoutine(hour: Int, minute: Int = 0,
                           recurrence: RecurrenceKind = .daily, weekdays: [Int]? = nil) -> Routine {
        let t = cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        let routine = Routine(name: "B\(hour)", timeOfDay: t,
                          recurrenceKind: recurrence, weekdays: weekdays)
        context.insert(routine)

        let med = Medication(name: "Med\(hour)")
        context.insert(med)
        context.insert(RoutineItem(quantity: 1.0, medication: med, routine: routine))
        try? context.save()
        return routine
    }

    /// `now` set to 1 hour before the routine slot today, so all reminders are in the future.
    private func nowBefore(_ routine: Routine) -> Date {
        DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(-3600)
    }

    @Test
    func testDailyRoutineEmitsHeadsUpDueAndThreeFollowUps() {
        let routine = makeRoutine(hour: 9)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        let kinds = plan.map(\.kind).sorted { $0.rawValue < $1.rawValue }
        #expect(plan.count == 5)   // headsUp + due + 3 follow-ups (30/60/90)
        #expect(kinds.filter { $0 == .headsUp }.count == 1)
        #expect(kinds.filter { $0 == .due }.count == 1)
        #expect(kinds.filter { $0 == .followUp }.count == 3)
    }

    @Test
    func testHeadsUpDisabledDropsHeadsUp() {
        let routine = makeRoutine(hour: 9)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: false, masterEnabled: true)
        #expect(!plan.contains { $0.kind == .headsUp })
        #expect(plan.count == 4)
    }

    @Test
    func testFollowUpsClippedToGraceWindow() {
        let routine = makeRoutine(hour: 9)
        // 60-minute grace → only the +30 follow-up is strictly before the cutoff.
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 60, headsUpEnabled: true, masterEnabled: true)
        #expect(plan.filter { $0.kind == .followUp }.count == 1)
    }

    @Test
    func testMasterDisabledEmitsNothing() {
        let routine = makeRoutine(hour: 9)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: false)
        #expect(plan.isEmpty)
    }

    @Test
    func testPastFireDatesAreOmitted() {
        let routine = makeRoutine(hour: 9)
        // now = slot + 40 min → headsUp, due, +30 are in the past; only +60, +90 remain.
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(40 * 60)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: now, horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        #expect(plan.allSatisfy { $0.fireDate > now })
        #expect(plan.filter { $0.kind == .followUp }.count == 2)
    }

    @Test
    func testWeekdayRoutineAbsentOnExcludedDay() {
        let today = cal.component(.weekday, from: .now)
        let other = (today % 7) + 1   // a different weekday
        let routine = makeRoutine(hour: 9, recurrence: .weekdays, weekdays: [other])
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        #expect(plan.isEmpty)
    }

    @Test
    func testCompletedSlotIsSkipped() {
        let routine = makeRoutine(hour: 9)
        let slot = DayQuery.slotDate(for: routine, on: .now)
        let key = ReminderScheduler.slotKey(routineUUID: routine.uuid.uuidString, slot: slot)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true,
            completedSlots: [key])
        #expect(plan.isEmpty)
    }

    @Test
    func testRespectsLimit() {
        let routine = makeRoutine(hour: 9)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true, limit: 2)
        #expect(plan.count == 2)
        // earliest fire dates kept
        #expect(plan.map(\.fireDate) == plan.map(\.fireDate).sorted { $0 < $1 })
    }

    @Test
    func testIdentifiersAreUnique() {
        let routine = makeRoutine(hour: 9)
        let plan = ReminderScheduler.plan(
            routines: [routine], now: nowBefore(routine), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        #expect(Set(plan.map(\.identifier)).count == plan.count)
    }
}

