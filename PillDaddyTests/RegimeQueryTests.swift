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

        let active = MedicationService.addMedication(
            name: "Active", strength: "10mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = active

        let discontinued = MedicationService.addMedication(
            name: "Stopped", strength: "10mg", form: "tablet",
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
        _ = MedicationService.addMedication(
            name: "Tylenol", strength: "500mg", form: "tablet",
            isPRN: true, notes: "", placements: [], reason: "", in: context)
        let scheduled = MedicationService.addMedication(
            name: "Scheduled", strength: "1mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        _ = scheduled

        let prn = try RegimeQuery.activePRNMeds(in: context)
        #expect(prn.map(\.name) == ["Tylenol"])
    }
}

