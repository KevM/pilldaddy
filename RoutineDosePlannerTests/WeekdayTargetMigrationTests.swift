import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

// Serialized: mutates the process-global migration UserDefaults flag.
@Suite(.serialized)
@MainActor
struct WeekdayTargetMigrationTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    private func clearDatabase() throws {
        try context.delete(model: RoutineItem.self)
        try context.delete(model: Routine.self)
        try context.delete(model: Medication.self)
        try context.save()
    }

    @Test func partialWeekMedSnapshotsAndStaysFull() throws {
        try clearDatabase()
        let key = "didRunWeekdayTargetBackfill"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        context.insert(med)
        // Scheduled only Mon–Fri (weekdays 2–6) at 1.5.
        let routine = Routine(name: "Weekdays", recurrenceKind: .weekdays, weekdays: [2, 3, 4, 5, 6])
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.5, medication: med, routine: routine))
        try context.save()

        WeekdayTargetMigration.backfill(in: context)

        #expect(med.weekdayDoseTargets != nil)
        #expect(med.weekdayDoseTargets?[0] == 0)   // Sunday
        #expect(med.weekdayDoseTargets?[1] == 1.5) // Monday
        #expect(DoseAllocation.status(med) == .full)
    }

    @Test func uniformDailyMedStaysNil() throws {
        try clearDatabase()
        let key = "didRunWeekdayTargetBackfill"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let med = Medication(name: "Vitamin D", strengthValue: 1000, strengthUnit: "IU", dailyDoseTarget: 1)
        context.insert(med)
        let routine = Routine(name: "Daily", recurrenceKind: .daily)
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.0, medication: med, routine: routine))
        try context.save()

        WeekdayTargetMigration.backfill(in: context)

        #expect(med.weekdayDoseTargets == nil)
        #expect(DoseAllocation.status(med) == .full)
    }

    @Test func isIdempotent() throws {
        try clearDatabase()
        let key = "didRunWeekdayTargetBackfill"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        context.insert(med)
        let routine = Routine(name: "Weekdays", recurrenceKind: .weekdays, weekdays: [2, 3, 4, 5, 6])
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.5, medication: med, routine: routine))
        try context.save()

        WeekdayTargetMigration.backfill(in: context)
        // A second run must change nothing (flag already set).
        med.weekdayDoseTargets = nil
        WeekdayTargetMigration.backfill(in: context)
        #expect(med.weekdayDoseTargets == nil)
    }
}
