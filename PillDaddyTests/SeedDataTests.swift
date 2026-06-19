import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class SeedDataTests: XCTestCase {
    func testSeedPopulatesWorkedExampleRegime() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()

        // Metoprolol exists in two batches at 1.0 and 0.5
        let metoprolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Metoprolol" })).first)
        XCTAssertEqual(metoprolol.batchItems?.count, 2)
        XCTAssertEqual((metoprolol.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])

        // At least one PRN med
        let prnMeds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isPRN == true }))
        XCTAssertGreaterThanOrEqual(prnMeds.count, 1)

        // At least one change-event in the history
        let events = try context.fetch(FetchDescriptor<MedicationChangeEvent>())
        XCTAssertGreaterThanOrEqual(events.count, 1)
    }

    func testSeedIsIdempotent() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()
        let countAfterFirst = try context.fetch(FetchDescriptor<Medication>()).count

        SeedData.seedIfEmpty(context)   // second call must be a no-op
        try context.save()
        let countAfterSecond = try context.fetch(FetchDescriptor<Medication>()).count

        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }
}
