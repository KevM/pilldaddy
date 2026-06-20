import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct MedicationServiceTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test
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

        #expect(med.batchItems?.count == 2)
        #expect((med.batchItems ?? []).map(\.quantity).sorted() == [0.5, 1.0])
        let events = med.changeEvents ?? []
        #expect(events.count == 1)
        #expect(events.first?.eventType == MedChangeType.added.rawValue)
        #expect(events.first?.reasoning == "Started for hypertension")
    }

    @Test
    func testAddPRNMedicationIgnoresPlacements() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)

        let med = MedicationService.addMedication(
            name: "Acetaminophen", strength: "500mg", form: "tablet",
            isPRN: true, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)

        #expect(med.batchItems ?? [] == [])
        #expect(med.isPRN)
        #expect(med.changeEvents?.count == 1)
    }

    @Test
    func testChangeDoseMutatesQuantityAndWritesEvent() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        try MedicationService.changeDose(
            med, newStrength: "30mg",
            newQuantities: [(item: item, quantity: 0.5)],
            reason: "Reduced after dizziness", in: context)

        #expect(item.quantity == 0.5)
        let doseEvents = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.doseChanged.rawValue }
        #expect(doseEvents.count == 1)
        #expect(doseEvents.first?.oldValue == "30mg — Blue 1")
        #expect(doseEvents.first?.newValue == "30mg — Blue 0.5")
    }

    @Test
    func testChangeDoseWithEmptyReasonThrows() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.changeDose(med, newStrength: "15mg",
                newQuantities: [], reason: "   ", in: context)
        }
    }

    @Test
    func testChangeInstructionsUpdatesItemAndWritesEvent() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        try MedicationService.changeInstructions(
            item, newInstructions: "Take on empty stomach",
            reason: "Per pharmacist", in: context)

        #expect(item.instructionsOverride == "Take on empty stomach")
        let events = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.instructionsChanged.rawValue }
        #expect(events.count == 1)
        #expect(events.first?.newValue == "Take on empty stomach")
    }

    @Test
    func testChangeInstructionsWithEmptyReasonThrows() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.changeInstructions(item, newInstructions: "x", reason: "", in: context)
        }
    }

    @Test
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

        #expect(!old.isActive)
        #expect(old.discontinuedAt != nil)
        #expect(old.successor?.name == "Bisoprolol")
        #expect(new.batchItems?.count == 2)
        #expect((new.batchItems ?? []).map(\.quantity).sorted() == [0.5, 1.0])
        #expect((old.changeEvents ?? []).contains { $0.eventType == MedChangeType.swapped.rawValue })
        #expect((new.changeEvents ?? []).contains { $0.eventType == MedChangeType.added.rawValue })
        // Old med keeps its memberships (discontinue preserves history).
        #expect(old.batchItems?.count == 2)
    }

    @Test
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

        #expect(new.batchItems ?? [] == [])
        #expect(old.batchItems?.count == 1)
    }

    @Test
    func testSwapWithEmptyReasonThrows() throws {
        let old = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.swap(old, newName: "B", newStrength: "5mg",
                newForm: "tablet", inheritSchedule: true, reason: " ", in: context)
        }
    }

    @Test
    func testDiscontinueKeepsMembershipsAndMarksInactive() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)

        try MedicationService.discontinue(med, reason: "No longer needed", in: context)

        #expect(!med.isActive)
        #expect(med.discontinuedAt != nil)
        #expect(med.batchItems?.count == 1) // memberships preserved
        #expect((med.changeEvents ?? []).contains { $0.eventType == MedChangeType.discontinued.rawValue })
    }

    @Test
    func testReactivateRestoresActiveState() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        try MedicationService.discontinue(med, reason: "stop", in: context)

        try MedicationService.reactivate(med, reason: "Restarting", in: context)

        #expect(med.isActive)
        #expect(med.discontinuedAt == nil)
        #expect((med.changeEvents ?? []).contains { $0.eventType == MedChangeType.reactivated.rawValue })
    }

    @Test
    func testDiscontinueWithEmptyReasonThrows() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.discontinue(med, reason: "", in: context)
        }
    }

    @Test
    func testAddNoteWritesNoteEvent() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        try MedicationService.addNote(med, text: "Cardiologist confirmed dose at June visit", in: context)

        let notes = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.note.rawValue }
        #expect(notes.count == 1)
        #expect(notes.first?.reasoning == "Cardiologist confirmed dose at June visit")
    }

    @Test
    func testAddNoteWithEmptyTextThrowsAndWritesNothing() throws {
        let med = MedicationService.addMedication(
            name: "Metoprolol", strength: "30mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.addNote(med, text: "   ", in: context)
        }

        let notes = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.note.rawValue }
        #expect(notes.count == 0)
    }
}

