import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct DoseLogStrengthSnapshotTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test func prnLogFreezesNumericStrength() throws {
        let med = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg",
                             dailyDoseTarget: 1, isPRN: true)
        context.insert(med)

        let log = DoseLogService.logPRN(med, takenAt: .now, quantity: 2,
                                        note: "", in: context)

        #expect(log.snapshotStrengthValue == 500)
        #expect(log.snapshotStrengthUnit == "mg")

        // Editing the med later must not change the frozen snapshot.
        med.strengthValue = 250
        #expect(log.snapshotStrengthValue == 500)
        // Medicine received = frozen strength x quantity.
        #expect(log.snapshotStrengthValue * log.quantity == 1000)
    }
}
