import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogTests {

    @Test
    func testScheduledDoseLogLinksMedicationAndBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.0)
        let routine = Routine(name: "Blue", colorHex: "#3B82F6")
        let item = RoutineItem(quantity: 1.0, medication: med, routine: routine)
        context.insert(med); context.insert(routine); context.insert(item)

        let log = DoseLog(
            scheduledDate: .now, status: .taken, quantity: 1.0,
            snapshotMedName: "Metoprolol", snapshotStrength: "30 mg",
            medication: med, routineItem: item)
        context.insert(log)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<DoseLog>()).first)
        #expect(fetched.status == DoseStatus.taken.rawValue)
        #expect(fetched.snapshotMedName == "Metoprolol")
        #expect(fetched.medication?.name == "Metoprolol")
        #expect(fetched.routineItem?.quantity == 1.0)
        #expect(med.doseLogs?.count == 1)
    }

    @Test
    func testPRNDoseLogHasNoBatchItem() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let prn = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg", dailyDoseTarget: 1.0, isPRN: true)
        context.insert(prn)
        let log = DoseLog(status: .taken, quantity: 2.0,
                          snapshotMedName: "Acetaminophen", medication: prn, routineItem: nil)
        context.insert(log)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<DoseLog>()).first)
        #expect(fetched.routineItem == nil)
        #expect(fetched.medication?.name == "Acetaminophen")
    }
}

