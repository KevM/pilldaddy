import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class BatchRelationshipTests: XCTestCase {
    func testMedicationInTwoBatchesAtDifferentQuantities() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
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

        let fetchedMed = try XCTUnwrap(try context.fetch(FetchDescriptor<Medication>()).first)
        XCTAssertEqual(fetchedMed.batchItems?.count, 2)
        let quantities = (fetchedMed.batchItems ?? []).map(\.quantity).sorted()
        XCTAssertEqual(quantities, [0.5, 1.0])

        let fetchedBlue = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Batch>(
                predicate: #Predicate { $0.name == "Blue" })).first)
        XCTAssertEqual(fetchedBlue.items?.count, 1)
        XCTAssertEqual(fetchedBlue.items?.first?.medication?.name, "Metoprolol")
        XCTAssertEqual(fetchedBlue.items?.first?.quantity, 1.0)
    }

    func testDefaultsForBatch() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let batch = Batch()
        context.insert(batch)
        try context.save()
        XCTAssertEqual(batch.mealRelation, MealRelation.none.rawValue)
        XCTAssertEqual(batch.recurrenceKind, RecurrenceKind.daily.rawValue)
        XCTAssertEqual(batch.items ?? [], [])
    }
}
