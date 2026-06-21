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

        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.5,
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

        let med = try MedicationService.addMedication(
            name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg", form: "tablet",
            isPRN: true, notes: "", dailyDoseTarget: 1.0,
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
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(batch: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        try MedicationService.changeDose(
            med, newStrengthValue: 30, newStrengthUnit: "mg",
            newDailyDoseTarget: 1.0,
            newQuantities: [(item: item, quantity: 0.5)],
            reason: "Reduced after dizziness", in: context)

        #expect(item.quantity == 0.5)
        let doseEvents = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.doseChanged.rawValue }
        #expect(doseEvents.count == 1)
        #expect(doseEvents.first?.oldValue == "30 mg — Blue 1")
        #expect(doseEvents.first?.newValue == "30 mg — Blue 0.5")
    }

    @Test
    func testChangeDoseWithEmptyReasonThrows() throws {
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0, placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.changeDose(med, newStrengthValue: 15, newStrengthUnit: "mg",
                newDailyDoseTarget: 1.0,
                newQuantities: [], reason: "   ", in: context)
        }
    }

    @Test
    func testChangeInstructionsUpdatesItemAndWritesEvent() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
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
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
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
        let old = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.5,
            placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 0.5)],
            reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrengthValue: 5, newStrengthUnit: "mg", newForm: "tablet",
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
        let old = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrengthValue: 5, newStrengthUnit: "mg", newForm: "tablet",
            inheritSchedule: false, reason: "Switch", in: context)

        #expect(new.batchItems ?? [] == [])
        #expect(old.batchItems?.count == 1)
    }

    @Test
    func testSwapWithEmptyReasonThrows() throws {
        let old = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0, placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.swap(old, newName: "B", newStrengthValue: 5, newStrengthUnit: "mg",
                newForm: "tablet", inheritSchedule: true, reason: " ", in: context)
        }
    }

    @Test
    func testDiscontinueKeepsMembershipsAndMarksInactive() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)

        try MedicationService.discontinue(med, reason: "No longer needed", in: context)

        #expect(!med.isActive)
        #expect(med.discontinuedAt != nil)
        #expect(med.batchItems?.count == 1) // memberships preserved
        #expect((med.changeEvents ?? []).contains { $0.eventType == MedChangeType.discontinued.rawValue })
    }

    @Test
    func testReactivateRestoresActiveState() throws {
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0, placements: [], reason: "", in: context)
        try MedicationService.discontinue(med, reason: "stop", in: context)

        try MedicationService.reactivate(med, reason: "Restarting", in: context)

        #expect(med.isActive)
        #expect(med.discontinuedAt == nil)
        #expect((med.changeEvents ?? []).contains { $0.eventType == MedChangeType.reactivated.rawValue })
    }

    @Test
    func testDiscontinueWithEmptyReasonThrows() throws {
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0, placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.discontinue(med, reason: "", in: context)
        }
    }

    @Test
    func testAddNoteWritesNoteEvent() throws {
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0, placements: [], reason: "", in: context)

        try MedicationService.addNote(med, text: "Cardiologist confirmed dose at June visit", in: context)

        let notes = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.note.rawValue }
        #expect(notes.count == 1)
        #expect(notes.first?.reasoning == "Cardiologist confirmed dose at June visit")
    }

    @Test
    func testAddNoteWithEmptyTextThrowsAndWritesNothing() throws {
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0, placements: [], reason: "", in: context)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.addNote(med, text: "   ", in: context)
        }

        let notes = (med.changeEvents ?? []).filter { $0.eventType == MedChangeType.note.rawValue }
        #expect(notes.count == 0)
    }

    @Test
    func testAddToBatchWithinRemainingInserts() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 2,
            placements: [], reason: "", in: context)

        try MedicationService.addToBatch(med, blue, quantity: 1.5, in: context)

        #expect(med.batchItems?.count == 1)
        #expect(DoseAllocation.allocated(med) == 1.5)
    }

    @Test
    func testAddToBatchExceedingRemainingThrows() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [], reason: "", in: context)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToBatch(med, blue, quantity: 1.5, in: context)
        }
        #expect(med.batchItems?.isEmpty == true)
    }

    @Test
    func testChangeDoseRejectsResultingOverAllocation() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.changeDose(
                med, newStrengthValue: 30, newStrengthUnit: "mg",
                newDailyDoseTarget: 1,
                newQuantities: [(item: item, quantity: 2.0)],
                reason: "bump", in: context)
        }
    }

    @Test
    func testChangeDoseWithRaisedTargetPermitsNewAllocation() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.batchItems?.first)

        try MedicationService.changeDose(
            med, newStrengthValue: 30, newStrengthUnit: "mg",
            newDailyDoseTarget: 2,
            newQuantities: [(item: item, quantity: 2.0)],
            reason: "increase", in: context)

        #expect(item.quantity == 2.0)
        #expect(med.dailyDoseTarget == 2)
    }

    @Test
    func testAddMedicationRejectsPlacementsOverTarget() throws {
        let blue = Batch(name: "Blue")
        let green = Batch(name: "Green")
        context.insert(blue); context.insert(green)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addMedication(
                name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
                isPRN: false, notes: "", dailyDoseTarget: 1,
                placements: [(batch: blue, quantity: 1.0), (batch: green, quantity: 1.0)],
                reason: "", in: context)
        }
    }

    @Test
    func testAddToBatchWritesScheduleChangedEvent() throws {
        let blue = Batch(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        try context.save()

        try MedicationService.addToBatch(med, blue, quantity: 1.0, in: context)

        #expect(med.batchItems?.count == 1)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "")
        #expect(event.newValue == "Morning · 1 tablet")
        #expect(event.reasoning == "")
    }

    @Test
    func testAddToBatchStillEnforcesAllocationCap() throws {
        let blue = Batch(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet")
        context.insert(med)
        try context.save()

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToBatch(med, blue, quantity: 2.0, in: context)
        }
    }

    @Test
    func testRemoveFromBatchDeletesItemAndWritesEvent() throws {
        let blue = Batch(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet")
        context.insert(med)
        let item = BatchItem(quantity: 1.0, medication: med, batch: blue)
        context.insert(item)
        try context.save()

        try MedicationService.removeFromBatch(item, in: context)

        #expect(med.batchItems?.isEmpty == true)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "Morning · 1 tablet")
        #expect(event.newValue == "")
    }

    @Test
    func testMoveToBatchPreservesQuantityAndWritesOldNewEvent() throws {
        let morning = Batch(name: "Morning")
        let afternoon = Batch(name: "Afternoon")
        context.insert(morning); context.insert(afternoon)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        let item = BatchItem(quantity: 1.5, medication: med, batch: morning)
        context.insert(item)
        try context.save()

        try MedicationService.moveToBatch(item, to: afternoon, in: context)

        #expect(item.batch?.name == "Afternoon")
        #expect(item.quantity == 1.5)
        #expect(DoseAllocation.allocated(med) == 1.5)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "Morning · 1.5 tablet")
        #expect(event.newValue == "Afternoon · 1.5 tablet")
    }

    @Test
    func testMoveToBatchRejectsDuplicateMembership() throws {
        let morning = Batch(name: "Morning")
        let afternoon = Batch(name: "Afternoon")
        context.insert(morning); context.insert(afternoon)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        let inMorning = BatchItem(quantity: 1.0, medication: med, batch: morning)
        let inAfternoon = BatchItem(quantity: 1.0, medication: med, batch: afternoon)
        context.insert(inMorning); context.insert(inAfternoon)
        try context.save()

        #expect(throws: MembershipError.alreadyInBatch) {
            try MedicationService.moveToBatch(inMorning, to: afternoon, in: context)
        }
    }

    @Test
    func testDeleteBatchThrowsWhenActiveMedicationPresent() throws {
        let batch = Batch(name: "Morning")
        context.insert(batch)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet", isActive: true)
        context.insert(med)
        context.insert(BatchItem(quantity: 1.0, medication: med, batch: batch))
        try context.save()

        #expect(throws: BatchError.hasActiveMedications) {
            try MedicationService.deleteBatch(batch, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<Batch>()).count == 1)
    }

    @Test
    func testDeleteBatchSucceedsWhenNoActiveMedsAndPreservesDoseLogSnapshots() throws {
        let batch = Batch(name: "Morning", colorHex: "#3B82F6")
        context.insert(batch)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet", isActive: false)
        context.insert(med)
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(item)
        let log = DoseLog(scheduledDate: .now, takenAt: .now, status: .taken, quantity: 1.0,
                          snapshotMedName: "Metoprolol", snapshotStrength: "30 mg",
                          snapshotStrengthValue: 30, snapshotStrengthUnit: "mg",
                          medication: med, batchItem: item)
        context.insert(log)
        try context.save()

        try MedicationService.deleteBatch(batch, in: context)

        #expect(try context.fetch(FetchDescriptor<Batch>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BatchItem>()).isEmpty)   // cascade removed the join row
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.batchItem == nil)                              // link nullified
        #expect(logs.first?.snapshotMedName == "Metoprolol")              // snapshot survives
    }

    @Test
    func testAddToBatchRejectsDuplicateMembership() throws {
        let blue = Batch(name: "Blue")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        try context.save()

        try MedicationService.addToBatch(med, blue, quantity: 1.0, in: context)

        #expect(throws: MembershipError.alreadyInBatch) {
            try MedicationService.addToBatch(med, blue, quantity: 1.0, in: context)
        }
    }
}

