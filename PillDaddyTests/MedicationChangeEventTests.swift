import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationChangeEventTests: XCTestCase {
    func testChangeEventAttachesToMedication() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strength: "30mg")
        context.insert(med)
        let event = MedicationChangeEvent(
            type: .doseChanged, reasoning: "Lowered for low BP",
            oldValue: "30mg", newValue: "15mg", medication: med)
        context.insert(event)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<MedicationChangeEvent>()).first)
        XCTAssertEqual(fetched.eventType, MedChangeType.doseChanged.rawValue)
        XCTAssertEqual(fetched.reasoning, "Lowered for low BP")
        XCTAssertEqual(fetched.medication?.name, "Metoprolol")
        XCTAssertEqual(med.changeEvents?.count, 1)
    }

    func testSwapLinksOldAndNewMedicationBothDirections() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let atenolol = Medication(name: "Atenolol", strength: "50mg")
        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
        context.insert(atenolol); context.insert(metoprolol)

        // perform a swap: discontinue old, link successor
        atenolol.isActive = false
        atenolol.discontinuedAt = .now
        atenolol.successor = metoprolol
        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: "Switched beta blocker for better tolerance",
            medication: atenolol))
        try context.save()

        let fetchedAtenolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Atenolol" })).first)
        XCTAssertFalse(fetchedAtenolol.isActive)
        XCTAssertEqual(fetchedAtenolol.successor?.name, "Metoprolol")
        XCTAssertEqual(fetchedAtenolol.successor?.predecessor?.name, "Atenolol")
    }
}
