import SwiftData
import Testing
@testable import RoutineDosePlanner

// Serialized to be safe and sequential.
@Suite(.serialized)
@MainActor
struct DoseSummaryFormatterTests {

    private static let container: ModelContainer = {
        try! ModelTestSupport.makeContainer()
    }()
    
    private var context: ModelContext {
        Self.container.mainContext
    }

    private func clearDatabase() throws {
        try context.delete(model: RoutineItem.self)
        try context.delete(model: Routine.self)
        try context.delete(model: Medication.self)
        try context.save()
    }

    @Test func uniformSummaryShowsPerDayCountAndStrength() throws {
        try clearDatabase()
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.5, form: "tablet")
        context.insert(med)
        #expect(DoseSummaryFormatter.summary(for: med) == "1.5 tablet/day · 45 mg/day")
    }

    @Test func variableSummaryListsDosingDaysAndWeeklyTotal() throws {
        try clearDatabase()
        let med = Medication(name: "Warfarin", strengthValue: 5, strengthUnit: "mg",
                             dailyDoseTarget: 0, form: "tablet")
        var perWeekday = Array(repeating: 0.0, count: 7)
        perWeekday[4] = 1; perWeekday[6] = 2 // Thu 1, Sat 2
        med.weekdayDoseTargets = perWeekday
        context.insert(med)
        #expect(DoseSummaryFormatter.summary(for: med) == "Thu 1 · Sat 2 · 3 tablet/wk")
    }

    @Test func mismatchNilWhenFull() throws {
        try clearDatabase()
        let med = Medication(name: "Daily", strengthValue: 10, strengthUnit: "mg",
                             dailyDoseTarget: 1, form: "tablet")
        context.insert(med)
        let routine = Routine(name: "Daily", recurrenceKind: .daily)
        context.insert(routine)
        context.insert(RoutineItem(quantity: 1.0, medication: med, routine: routine))
        #expect(DoseSummaryFormatter.mismatch(for: med) == nil)
    }

    @Test func mismatchNamesOverDay() throws {
        try clearDatabase()
        let med = Medication(name: "Daily", strengthValue: 10, strengthUnit: "mg",
                             dailyDoseTarget: 1, form: "tablet")
        context.insert(med)
        context.insert(RoutineItem(quantity: 1.0, medication: med,
                                   routine: insertRoutine(.daily, nil)))
        context.insert(RoutineItem(quantity: 1.0, medication: med,
                                   routine: insertRoutine(.weekdays, [7]))) // extra Saturday
        #expect(DoseSummaryFormatter.mismatch(for: med) == "Sat: 2 of 1 tablet")
    }

    @Test func recurrenceLabelNilForDaily() {
        #expect(RecurrenceLabel.short(for: Routine(name: "D", recurrenceKind: .daily)) == nil)
    }

    @Test func recurrenceLabelListsWeekdays() {
        let r = Routine(name: "W", recurrenceKind: .weekdays, weekdays: [7, 5])
        #expect(RecurrenceLabel.short(for: r) == "Thu, Sat")
    }

    private func insertRoutine(_ kind: RecurrenceKind, _ days: [Int]?) -> Routine {
        let r = Routine(name: "R", recurrenceKind: kind, weekdays: days)
        context.insert(r)
        return r
    }
}
