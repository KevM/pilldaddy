import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct BatchRelationshipTests {
    @Test
    func testMedicationInTwoBatchesAtDifferentQuantities() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let metoprolol = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        let blue = Batch(name: "Blue", colorHex: "#3B82F6")
        let green = Batch(name: "Green", colorHex: "#10B981")
        context.insert(metoprolol)
        context.insert(blue)
        context.insert(green)

        let morning = BatchItem(quantity: 1.0, medication: metoprolol, batch: blue)
        let evening = BatchItem(quantity: 0.5, medication: metoprolol, batch: green)
        context.insert(morning)
        context.insert(evening)
        try context.save()

        let fetchedMed = try #require(try context.fetch(FetchDescriptor<Medication>()).first)
        #expect(fetchedMed.batchItems?.count == 2)
        let quantities = (fetchedMed.batchItems ?? []).map(\.quantity).sorted()
        #expect(quantities == [0.5, 1.0])

        let fetchedBlue = try #require(
            try context.fetch(FetchDescriptor<Batch>(
                predicate: #Predicate { $0.name == "Blue" })).first)
        #expect(fetchedBlue.items?.count == 1)
        #expect(fetchedBlue.items?.first?.medication?.name == "Metoprolol")
        #expect(fetchedBlue.items?.first?.quantity == 1.0)
    }

    @Test
    func testDefaultsForBatch() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let batch = Batch()
        context.insert(batch)
        try context.save()
        #expect(batch.mealRelation == MealRelation.none.rawValue)
        #expect(batch.recurrenceKind == RecurrenceKind.daily.rawValue)
        #expect(batch.items ?? [] == [])
    }

    @Test
    func testBatchHasStableDistinctUUID() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let a = Batch(name: "A")
        let b = Batch(name: "B")
        context.insert(a); context.insert(b)
        try context.save()
        #expect(a.uuid != b.uuid)
        let savedID = a.uuid
        #expect(a.uuid == savedID)   // stable across access
    }
}


