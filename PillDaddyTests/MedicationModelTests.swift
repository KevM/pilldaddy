import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationModelTests: XCTestCase {
    func testInsertedMedicationHasExpectedDefaults() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strength: "30mg")
        context.insert(med)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Medication>())
        XCTAssertEqual(fetched.count, 1)
        let only = try XCTUnwrap(fetched.first)
        XCTAssertEqual(only.name, "Metoprolol")
        XCTAssertEqual(only.strength, "30mg")
        XCTAssertEqual(only.form, "tablet")
        XCTAssertTrue(only.isActive)
        XCTAssertFalse(only.isPRN)
        XCTAssertEqual(only.batchItems ?? [], [])
        XCTAssertNil(only.successor)
    }
}
