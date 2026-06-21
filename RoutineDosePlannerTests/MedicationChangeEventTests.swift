import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct MedicationChangeEventTests {
    @Test
    func testChangeEventAttachesToMedication() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.0)
        context.insert(med)
        let event = MedicationChangeEvent(
            type: .doseChanged, reasoning: "Lowered for low BP",
            oldValue: "30mg", newValue: "15mg", medication: med)
        context.insert(event)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<MedicationChangeEvent>()).first)
        #expect(fetched.eventType == MedChangeType.doseChanged.rawValue)
        #expect(fetched.reasoning == "Lowered for low BP")
        #expect(fetched.medication?.name == "Metoprolol")
        #expect(med.changeEvents?.count == 1)
    }

    @Test
    func testSwapLinksOldAndNewMedicationBothDirections() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let atenolol = Medication(name: "Atenolol", strengthValue: 50, strengthUnit: "mg", dailyDoseTarget: 1.0)
        let metoprolol = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.0)
        context.insert(atenolol); context.insert(metoprolol)

        // perform a swap: discontinue old, link successor
        atenolol.isActive = false
        atenolol.discontinuedAt = .now
        atenolol.successor = metoprolol
        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: "Switched beta blocker for better tolerance",
            medication: atenolol))
        try context.save()

        let fetchedAtenolol = try #require(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Atenolol" })).first)
        #expect(!fetchedAtenolol.isActive)
        #expect(fetchedAtenolol.successor?.name == "Metoprolol")
        #expect(fetchedAtenolol.successor?.predecessor?.name == "Atenolol")
    }
}

