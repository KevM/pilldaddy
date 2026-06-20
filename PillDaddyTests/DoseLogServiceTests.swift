import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogServiceTests {

    private let container: ModelContainer
    private let context: ModelContext
    private let blue: Batch

    init() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        let blue = Batch(name: "Blue", colorHex: "#3B82F6", timeOfDay: .now, sortOrder: 0)
        context.insert(blue)

        self.container = container
        self.context = context
        self.blue = blue
    }

    private func addMed(_ name: String, qty: Double) -> BatchItem {
        let med = MedicationService.addMedication(
            name: name, strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: qty)], reason: "", in: context)
        return (med.batchItems ?? []).first!
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    @Test
    func testLogBatchTakenWritesOneRowPerItemWithSnapshotsAndQuantity() throws {
        let a = addMed("A", qty: 0.5)
        let b = addMed("B", qty: 1.0)
        let at = Date.now
        DoseLogService.logBatchTaken(blue, on: .now, items: [a, b], takenAt: at, note: "", in: context)

        let all = try logs()
        #expect(all.count == 2)
        let aLog = try #require(all.first { $0.snapshotMedName == "A" })
        #expect(aLog.status == DoseStatus.taken.rawValue)
        #expect(aLog.quantity == 0.5)
        #expect(aLog.snapshotStrength == "10mg")
        #expect(aLog.snapshotBatchColorHex == "#3B82F6")
        #expect(aLog.takenAt == at)
    }

    @Test
    func testLogBatchTakenIsIdempotentUpsert() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        #expect(try logs().count == 1)   // updated, not duplicated
    }

    @Test
    func testLogBatchTakenLeavesUntouchedItemsAlone() throws {
        let a = addMed("A", qty: 1.0)
        let b = addMed("B", qty: 1.0)
        // B already skipped individually
        try DoseLogService.logMed(b, on: .now, status: .skipped, takenAt: nil, note: "BP low", in: context)
        // Batch-take only A (fill set excludes B)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)

        let bLog = try #require(try logs().first { $0.snapshotMedName == "B" })
        #expect(bLog.status == DoseStatus.skipped.rawValue)   // skip preserved
        #expect(bLog.notes == "BP low")
        #expect(try logs().count == 2)
    }

    @Test
    func testLogMedSkipRequiresNote() throws {
        let a = addMed("A", qty: 1.0)
        #expect(throws: DoseLogServiceError.noteRequired) {
            try DoseLogService.logMed(a, on: .now, status: .skipped, takenAt: nil, note: "  ", in: context)
        }
        #expect(try logs().count == 0)
    }

    @Test
    func testLogMedTakenAllowsEmptyNoteAndClearsTakenAtOnSkip() throws {
        let a = addMed("A", qty: 1.0)
        try DoseLogService.logMed(a, on: .now, status: .taken, takenAt: .now, note: "", in: context)
        #expect(try #require(try logs().first).takenAt != nil)
        try DoseLogService.logMed(a, on: .now, status: .skipped, takenAt: nil, note: "held", in: context)
        let log = try #require(try logs().first)
        #expect(log.status == DoseStatus.skipped.rawValue)
        #expect(log.takenAt == nil)
        #expect(try logs().count == 1)   // same row, upserted
    }

    @Test
    func testRevertDeletesTheSlotRow() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        DoseLogService.revert(a, on: .now, in: context)
        #expect(try logs().count == 0)
    }

    @Test
    func testRevertBatchDeletesAllSlotRows() throws {
        let a = addMed("A", qty: 1.0)
        let b = addMed("B", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a, b], takenAt: .now, note: "", in: context)
        DoseLogService.revertBatch(blue, on: .now, items: [a, b], in: context)
        #expect(try logs().count == 0)
    }

    @Test
    func testSnapshotStaysFrozenAfterRename() throws {
        let a = addMed("A", qty: 1.0)
        DoseLogService.logBatchTaken(blue, on: .now, items: [a], takenAt: .now, note: "", in: context)
        a.medication?.name = "Renamed"
        try context.save()
        #expect(try #require(try logs().first).snapshotMedName == "A")
    }
}

