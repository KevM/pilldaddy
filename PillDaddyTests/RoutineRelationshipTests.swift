import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct RoutineRelationshipTests {
    @Test
    func testMedicationInTwoRoutinesAtDifferentQuantities() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let metoprolol = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        let blue = Routine(name: "Blue", colorHex: "#3B82F6")
        let green = Routine(name: "Green", colorHex: "#10B981")
        context.insert(metoprolol)
        context.insert(blue)
        context.insert(green)

        let morning = RoutineItem(quantity: 1.0, medication: metoprolol, routine: blue)
        let evening = RoutineItem(quantity: 0.5, medication: metoprolol, routine: green)
        context.insert(morning)
        context.insert(evening)
        try context.save()

        let fetchedMed = try #require(try context.fetch(FetchDescriptor<Medication>()).first)
        #expect(fetchedMed.routineItems?.count == 2)
        let quantities = (fetchedMed.routineItems ?? []).map(\.quantity).sorted()
        #expect(quantities == [0.5, 1.0])

        let fetchedBlue = try #require(
            try context.fetch(FetchDescriptor<Routine>(
                predicate: #Predicate { $0.name == "Blue" })).first)
        #expect(fetchedBlue.items?.count == 1)
        #expect(fetchedBlue.items?.first?.medication?.name == "Metoprolol")
        #expect(fetchedBlue.items?.first?.quantity == 1.0)
    }

    @Test
    func testDefaultsForRoutine() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let routine = Routine()
        context.insert(routine)
        try context.save()
        #expect(routine.mealRelation == MealRelation.none.rawValue)
        #expect(routine.recurrenceKind == RecurrenceKind.daily.rawValue)
        #expect(routine.items ?? [] == [])
    }

    @Test
    func testRoutineHasStableDistinctUUID() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let a = Routine(name: "A")
        let b = Routine(name: "B")
        context.insert(a); context.insert(b)
        try context.save()
        #expect(a.uuid != b.uuid)
        let savedID = a.uuid
        #expect(a.uuid == savedID)   // stable across access
    }

    @Test
    func deletingRoutineKeepsDoseLogs() throws {
        let container = try ModelContainer(
            for: PillDaddySchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let med = Medication(name: "Test", isActive: false)
        let routine = Routine(name: "Morning")
        let item = RoutineItem(medication: med, routine: routine)
        let log = DoseLog(status: .taken, medication: med, routineItem: item)
        ctx.insert(med)
        ctx.insert(routine)
        ctx.insert(item)
        ctx.insert(log)
        try ctx.save()

        try MedicationService.deleteRoutine(routine, in: ctx)
        try ctx.save()

        let logs = try ctx.fetch(FetchDescriptor<DoseLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.routineItem == nil)
    }
}


