import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DoseLogServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var blue: Batch!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
        blue = Batch(name: "Blue", colorHex: "#3B82F6", timeOfDay: .now, sortOrder: 0)
        context.insert(blue)
    }

    override func tearDown() async throws {
        blue = nil; context = nil; container = nil
        try await super.tearDown()
    }

    private func addMed(_ name: String, qty: Double) -> BatchItem {
        let med = MedicationService.addMedication(
            name: name, strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: qty)], reason: "", in: context)
        return (med.batchItems ?? []).first!
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    func testLogBatchTakenWritesOneRowPerItemWithSnapshotsAndQuantity() throws {
        let a = addMed("A", qty: 0.5)
        let b = addMed("B", qty: 1.0)
        let at = Date.now
        DoseLogService.logBatchTaken(blue, on: .now, items: [a, b], takenAt: at, note: "", in: context)

        let all = try logs()
        XCTAssertEqual(all.count, 2)
        let aLog = try XCTUnwrap(all.first { $0.snapshotMedName == "A" })
        XCTAssertEqual(aLog.status, DoseStatus.taken.rawValue)
        XCTAssertEqual(aLog.quantity, 0.5)
        XCTAssertEqual(aLog.snapshotStrength, "10mg")
        XCTAssertEqual(aLog.snapshotBatchColorHex, "#3B82F6")
        XCTAssertEqual(aLog.takenAt, at)
    }

    func testLogBatchTakenIsIdempotentUpsert() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        XCTAssertEqual(try logs().count, 1)   // updated, not duplicated
    }

    func testLogBatchTakenLeavesUntouchedItemsAlone() throws {
        let a = addMed("A", qty: 1.0)
        let b = addMed("B", qty: 1.0)
        // B already skipped individually
        try DoseLogService.logMed(b, on: .now, status: .skipped, takenAt: nil, note: "BP low", in: context)
        // Batch-take only A (fill set excludes B)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)

        let bLog = try XCTUnwrap(try logs().first { $0.snapshotMedName == "B" })
        XCTAssertEqual(bLog.status, DoseStatus.skipped.rawValue)   // skip preserved
        XCTAssertEqual(bLog.notes, "BP low")
        XCTAssertEqual(try logs().count, 2)
    }

    func testLogMedSkipRequiresNote() throws {
        let a = addMed("A", qty: 1.0)
        XCTAssertThrowsError(
            try DoseLogService.logMed(a, on: .now, status: .skipped, takenAt: nil, note: "  ", in: context)
        ) { XCTAssertEqual($0 as? DoseLogServiceError, .noteRequired) }
        XCTAssertEqual(try logs().count, 0)
    }

    func testLogMedTakenAllowsEmptyNoteAndClearsTakenAtOnSkip() throws {
        let a = addMed("A", qty: 1.0)
        try DoseLogService.logMed(a, on: .now, status: .taken, takenAt: .now, note: "", in: context)
        XCTAssertEqual(try XCTUnwrap(try logs().first).takenAt != nil, true)
        try DoseLogService.logMed(a, on: .now, status: .skipped, takenAt: nil, note: "held", in: context)
        let log = try XCTUnwrap(try logs().first)
        XCTAssertEqual(log.status, DoseStatus.skipped.rawValue)
        XCTAssertNil(log.takenAt)
        XCTAssertEqual(try logs().count, 1)   // same row, upserted
    }

    func testRevertDeletesTheSlotRow() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        DoseLogService.revert(a, on: .now, in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testRevertBatchDeletesAllSlotRows() throws {
        let a = addMed("A", qty: 1.0)
        let b = addMed("B", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a, b], takenAt: .now, note: "", in: context)
        DoseLogService.revertBatch(blue, on: .now, items: [a, b], in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testSnapshotStaysFrozenAfterRename() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        a.medication?.name = "Renamed"
        try context.save()
        XCTAssertEqual(try XCTUnwrap(try logs().first).snapshotMedName, "A")
    }
}
