import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct RegimeQueryTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test
    func testActiveBatchGroupsExcludeDiscontinuedAndPRN() throws {
        let blue = Batch(name: "Blue", sortOrder: 0)
        context.insert(blue)

        let active = try MedicationService.addMedication(
            name: "Active", strengthValue: 10, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = active

        let discontinued = try MedicationService.addMedication(
            name: "Stopped", strengthValue: 10, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        try MedicationService.discontinue(discontinued, reason: "stop", in: context)

        let groups = try RegimeQuery.activeBatchGroups(in: context)
        #expect(groups.count == 1)
        #expect(groups.first?.items.count == 1)
        #expect(groups.first?.items.first?.medication?.name == "Active")
    }

    @Test
    func testActivePRNMedsReturnsOnlyActivePRN() throws {
        _ = try MedicationService.addMedication(
            name: "Tylenol", strengthValue: 500, strengthUnit: "mg", form: "tablet",
            isPRN: true, notes: "", placements: [], reason: "", in: context)
        let scheduled = try MedicationService.addMedication(
            name: "Scheduled", strengthValue: 1, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        _ = scheduled

        let prn = try RegimeQuery.activePRNMeds(in: context)
        #expect(prn.map(\.name) == ["Tylenol"])
    }
}

