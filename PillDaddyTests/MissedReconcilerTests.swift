import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct MissedReconcilerTests {

    private let container: ModelContainer
    private let context: ModelContext
    private var cal: Calendar { Calendar.current }

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @discardableResult
    private func makeBatch(hour: Int, recurrence: RecurrenceKind = .daily,
                           weekdays: [Int]? = nil) -> (Routine, RoutineItem) {
        let t = cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        let routine = Routine(name: "B\(hour)", timeOfDay: t,
                          recurrenceKind: recurrence, weekdays: weekdays)
        context.insert(routine)

        let med = Medication(name: "Med\(hour)")
        context.insert(med)
        let item = RoutineItem(quantity: 1.0, medication: med, routine: routine)
        context.insert(item)
        try? context.save()
        return (routine, item)
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    @Test
    func testWritesMissedForUnloggedSlotPastGrace() throws {
        let (routine, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        let all = try logs()
        #expect(all.count == 1)
        #expect(all.first?.status == DoseStatus.missed.rawValue)
        #expect(all.first?.takenAt == nil)
        #expect(all.first?.snapshotMedName == "Med9")
    }

    @Test
    func testDoesNotWriteBeforeGrace() throws {
        let (routine, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(60 * 60)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        #expect(try logs().count == 0)
    }

    @Test
    func testPreservesExistingTakenOrSkipped() throws {
        let (routine, item) = makeBatch(hour: 9)
        DoseLogService.logBatchTaken(routine, on: .now, items: [item], takenAt: .now, note: "", in: context)
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        let all = try logs()
        #expect(all.count == 1)
        #expect(all.first?.status == DoseStatus.taken.rawValue)
    }

    @Test
    func testIdempotent() throws {
        let (routine, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        #expect(try logs().count == 1)
    }

    @Test
    func testExcludesDiscontinuedMed() throws {
        let (routine, item) = makeBatch(hour: 9)
        item.medication?.isActive = false
        try context.save()
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        #expect(try logs().count == 0)
    }

    @Test
    func testRespectsWeekdayRecurrence() throws {
        let today = cal.component(.weekday, from: .now)
        let other = (today % 7) + 1
        let (routine, _) = makeBatch(hour: 9, recurrence: .weekdays, weekdays: [other])
        let now = DayQuery.slotDate(for: routine, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(routines: [routine], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        #expect(try logs().count == 0)
    }
}

