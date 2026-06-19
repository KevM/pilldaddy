import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationServiceTests: XCTestCase {

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

    func testAddScheduledMedicationCreatesBatchItemsAndAddedEvent() throws {
        let blue = Batch(name: "Blue", colorHex: "#3B82F6")
        let green = Batch(name: "Green", colorHex: "#10B981")
        context.insert(blue)
        context.insert(green)

        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 0.5)],
            reason: "Started for hypertension", in: context)

        XCTAssertEqual(med.batchItems?.count, 2)
        XCTAssertEqual((med.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])
        let events = med.changeEvents ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.eventType, MedChangeType.added.rawValue)
        XCTAssertEqual(events.first?.reasoning, "Started for hypertension")
    }

    func testAddPRNMedicationIgnoresPlacements() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)

        let med = MedicationService.addMedication(
            name: "Acetaminophen", strength: "500mg", form: "tablet",
            isPRN: true, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)

        XCTAssertEqual(med.batchItems ?? [], [])
        XCTAssertTrue(med.isPRN)
        XCTAssertEqual(med.changeEvents?.count, 1)
    }

    func testChangeDoseMutatesQuantityAndWritesEvent() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try XCTUnwrap(med.batchItems?.first)

        try MedicationService.changeDose(
            med, newStrength: "30mg",
            newQuantities: [(item: item, quantity: 0.5)],
            reason: "Reduced after dizziness", in: context)

        XCTAssertEqual(item.quantity, 0.5)
        let doseEvents = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.doseChanged.rawValue }
        XCTAssertEqual(doseEvents.count, 1)
        XCTAssertEqual(doseEvents.first?.oldValue, "30mg — Blue 1")
        XCTAssertEqual(doseEvents.first?.newValue, "30mg — Blue 0.5")
    }

    func testChangeDoseWithEmptyReasonThrows() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        XCTAssertThrowsError(
            try MedicationService.changeDose(med, newStrength: "15mg",
                newQuantities: [], reason: "   ", in: context)
        ) { error in
            XCTAssertEqual(error as? MedicationServiceError, .reasonRequired)
        }
    }
}
