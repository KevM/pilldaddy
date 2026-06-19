import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class RegimeQueryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

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
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.items.count, 1)
        XCTAssertEqual(groups.first?.items.first?.medication?.name, "Active")
    }

    func testActivePRNMedsReturnsOnlyActivePRN() throws {
        _ = MedicationService.addMedication(
            name: "Tylenol", strength: "500mg", form: "tablet",
            isPRN: true, notes: "", placements: [], reason: "", in: context)
        let scheduled = MedicationService.addMedication(
            name: "Scheduled", strength: "1mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        _ = scheduled

        let prn = try RegimeQuery.activePRNMeds(in: context)
        XCTAssertEqual(prn.map(\.name), ["Tylenol"])
    }
}
