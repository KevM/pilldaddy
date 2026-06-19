import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DoseLogTests: XCTestCase {
    func testScheduledDoseLogLinksMedicationAndBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strength: "30mg")
        let batch = Batch(name: "Blue", colorHex: "#3B82F6")
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(med); context.insert(batch); context.insert(item)

        let log = DoseLog(
            scheduledDate: .now, status: .taken, quantity: 1.0,
            snapshotMedName: "Metoprolol", snapshotStrength: "30mg",
            snapshotBatchColorHex: "#3B82F6", medication: med, batchItem: item)
        context.insert(log)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<DoseLog>()).first)
        XCTAssertEqual(fetched.status, DoseStatus.taken.rawValue)
        XCTAssertEqual(fetched.snapshotMedName, "Metoprolol")
        XCTAssertEqual(fetched.medication?.name, "Metoprolol")
        XCTAssertEqual(fetched.batchItem?.quantity, 1.0)
        XCTAssertEqual(med.doseLogs?.count, 1)
    }

    func testPRNDoseLogHasNoBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let prn = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(prn)
        let log = DoseLog(status: .taken, quantity: 2.0,
                          snapshotMedName: "Acetaminophen", medication: prn, batchItem: nil)
        context.insert(log)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<DoseLog>()).first)
        XCTAssertNil(fetched.batchItem)
        XCTAssertEqual(fetched.medication?.name, "Acetaminophen")
    }
}
