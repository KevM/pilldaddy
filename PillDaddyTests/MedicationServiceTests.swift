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

    func testChangeInstructionsUpdatesItemAndWritesEvent() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try XCTUnwrap(med.batchItems?.first)

        try MedicationService.changeInstructions(
            item, newInstructions: "Take on empty stomach",
            reason: "Per pharmacist", in: context)

        XCTAssertEqual(item.instructionsOverride, "Take on empty stomach")
        let events = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.instructionsChanged.rawValue }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.newValue, "Take on empty stomach")
    }

    func testChangeInstructionsWithEmptyReasonThrows() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try XCTUnwrap(med.batchItems?.first)

        XCTAssertThrowsError(
            try MedicationService.changeInstructions(item, newInstructions: "x", reason: "", in: context)
        ) { XCTAssertEqual($0 as? MedicationServiceError, .reasonRequired) }
    }

    func testSwapInheritsScheduleDiscontinuesOldAndLinksSuccessor() throws {
        let blue = Batch(name: "Blue")
        let green = Batch(name: "Green")
        context.insert(blue)
        context.insert(green)
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 0.5)],
            reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrength: "5mg", newForm: "tablet",
            inheritSchedule: true, reason: "Cardiologist switch", in: context)

        XCTAssertFalse(old.isActive)
        XCTAssertNotNil(old.discontinuedAt)
        XCTAssertEqual(old.successor?.name, "Bisoprolol")
        XCTAssertEqual(new.batchItems?.count, 2)
        XCTAssertEqual((new.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])
        XCTAssertTrue((old.changeEvents ?? []).contains { $0.eventType == MedChangeType.swapped.rawValue })
        XCTAssertTrue((new.changeEvents ?? []).contains { $0.eventType == MedChangeType.added.rawValue })
        // Old med keeps its memberships (discontinue preserves history).
        XCTAssertEqual(old.batchItems?.count, 2)
    }

    func testSwapWithoutInheritLeavesNewUnscheduled() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrength: "5mg", newForm: "tablet",
            inheritSchedule: false, reason: "Switch", in: context)

        XCTAssertEqual(new.batchItems ?? [], [])
        XCTAssertEqual(old.batchItems?.count, 1)
    }

    func testSwapWithEmptyReasonThrows() throws {
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        XCTAssertThrowsError(
            try MedicationService.swap(old, newName: "B", newStrength: "5mg",
                newForm: "tablet", inheritSchedule: true, reason: " ", in: context)
        ) { XCTAssertEqual($0 as? MedicationServiceError, .reasonRequired) }
    }
}
