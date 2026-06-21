import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct MedicationModelTests {
    @Test
    func testInsertedMedicationHasExpectedDefaults() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.0)
        context.insert(med)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Medication>())
        #expect(fetched.count == 1)
        let only = try #require(fetched.first)
        #expect(only.name == "Metoprolol")
        #expect(only.strengthDescription == "30 mg")
        #expect(only.form == "tablet")
        #expect(only.isActive)
        #expect(!only.isPRN)
        #expect(only.routineItems ?? [] == [])
        #expect(only.successor == nil)
    }
}

