import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogTests {

    @Test
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

        let fetched = try #require(try context.fetch(FetchDescriptor<DoseLog>()).first)
        #expect(fetched.status == DoseStatus.taken.rawValue)
        #expect(fetched.snapshotMedName == "Metoprolol")
        #expect(fetched.medication?.name == "Metoprolol")
        #expect(fetched.batchItem?.quantity == 1.0)
        #expect(med.doseLogs?.count == 1)
    }

    @Test
    func testPRNDoseLogHasNoBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let prn = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(prn)
        let log = DoseLog(status: .taken, quantity: 2.0,
                          snapshotMedName: "Acetaminophen", medication: prn, batchItem: nil)
        context.insert(log)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<DoseLog>()).first)
        #expect(fetched.batchItem == nil)
        #expect(fetched.medication?.name == "Acetaminophen")
    }
}

