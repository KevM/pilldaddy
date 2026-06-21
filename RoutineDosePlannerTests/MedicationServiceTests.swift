import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct MedicationServiceTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test
    func testAddScheduledMedicationCreatesRoutineItemsAndAddedEvent() throws {
        let blue = Routine(name: "Blue", colorHex: "#3B82F6")
        let green = Routine(name: "Green", colorHex: "#10B981")
        context.insert(blue)
        context.insert(green)

        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.5,
            placements: [(routine: blue, quantity: 1.0), (routine: green, quantity: 0.5)],
            reason: "Started for hypertension", in: context)

        #expect(med.routineItems?.count == 2)
        #expect((med.routineItems ?? []).map(\.quantity).sorted() == [0.5, 1.0])
        let events = med.changeEvents ?? []
        #expect(events.count == 1)
        #expect(events.first?.eventType == MedChangeType.added.rawValue)
        #expect(events.first?.reasoning == "Started for hypertension")
    }

    @Test
    func testAddPRNMedicationIgnoresPlacements() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)

        let med = try MedicationService.addMedication(
            name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg", form: "tablet",
            isPRN: true, notes: "", dailyDoseTarget: 1.0,
            placements: [(routine: blue, quantity: 1.0)],
            reason: "", in: context)

        #expect(med.routineItems ?? [] == [])
        #expect(med.isPRN)
        #expect(med.changeEvents?.count == 1)
    }

    @Test
    func testChangeDoseMutatesQuantityAndWritesEvent() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(routine: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try #require(med.routineItems?.first)

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
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(routine: blue, quantity: 1.0)],
            reason: "", in: context)
        let item = try #require(med.routineItems?.first)

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
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.routineItems?.first)

        #expect(throws: MedicationServiceError.reasonRequired) {
            try MedicationService.changeInstructions(item, newInstructions: "x", reason: "", in: context)
        }
    }

    @Test
    func testSwapInheritsScheduleDiscontinuesOldAndLinksSuccessor() throws {
        let blue = Routine(name: "Blue")
        let green = Routine(name: "Green")
        context.insert(blue)
        context.insert(green)
        let old = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.5,
            placements: [(routine: blue, quantity: 1.0), (routine: green, quantity: 0.5)],
            reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrengthValue: 5, newStrengthUnit: "mg", newForm: "tablet",
            inheritSchedule: true, reason: "Cardiologist switch", in: context)

        #expect(!old.isActive)
        #expect(old.discontinuedAt != nil)
        #expect(old.successor?.name == "Bisoprolol")
        #expect(new.routineItems?.count == 2)
        #expect((new.routineItems ?? []).map(\.quantity).sorted() == [0.5, 1.0])
        #expect((old.changeEvents ?? []).contains { $0.eventType == MedChangeType.swapped.rawValue })
        #expect((new.changeEvents ?? []).contains { $0.eventType == MedChangeType.added.rawValue })
        // Old med keeps its memberships (discontinue preserves history).
        #expect(old.routineItems?.count == 2)
    }

    @Test
    func testSwapWithoutInheritLeavesNewUnscheduled() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let old = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)

        let new = try MedicationService.swap(
            old, newName: "Bisoprolol", newStrengthValue: 5, newStrengthUnit: "mg", newForm: "tablet",
            inheritSchedule: false, reason: "Switch", in: context)

        #expect(new.routineItems ?? [] == [])
        #expect(old.routineItems?.count == 1)
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
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1.0,
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)

        try MedicationService.discontinue(med, reason: "No longer needed", in: context)

        #expect(!med.isActive)
        #expect(med.discontinuedAt != nil)
        #expect(med.routineItems?.count == 1) // memberships preserved
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
    func testAddToRoutineWithinRemainingInserts() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 2,
            placements: [], reason: "", in: context)

        try MedicationService.addToRoutine(med, blue, quantity: 1.5, in: context)

        #expect(med.routineItems?.count == 1)
        #expect(DoseAllocation.allocated(med) == 1.5)
    }

    @Test
    func testAddToRoutineExceedingRemainingThrows() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [], reason: "", in: context)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToRoutine(med, blue, quantity: 1.5, in: context)
        }
        #expect(med.routineItems?.isEmpty == true)
    }

    @Test
    func testChangeDoseRejectsResultingOverAllocation() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.routineItems?.first)

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
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", dailyDoseTarget: 1,
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        let item = try #require(med.routineItems?.first)

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
        let blue = Routine(name: "Blue")
        let green = Routine(name: "Green")
        context.insert(blue); context.insert(green)

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addMedication(
                name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", form: "tablet",
                isPRN: false, notes: "", dailyDoseTarget: 1,
                placements: [(routine: blue, quantity: 1.0), (routine: green, quantity: 1.0)],
                reason: "", in: context)
        }
    }

    @Test
    func testAddToRoutineWritesScheduleChangedEvent() throws {
        let blue = Routine(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        try context.save()

        try MedicationService.addToRoutine(med, blue, quantity: 1.0, in: context)

        #expect(med.routineItems?.count == 1)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "")
        #expect(event.newValue == "Morning · 1 tablet")
        #expect(event.reasoning == "")
    }

    @Test
    func testAddToRoutineStillEnforcesAllocationCap() throws {
        let blue = Routine(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet")
        context.insert(med)
        try context.save()

        #expect(throws: DoseAllocationError.exceedsDailyTarget) {
            try MedicationService.addToRoutine(med, blue, quantity: 2.0, in: context)
        }
    }

    @Test
    func testRemoveFromRoutineDeletesItemAndWritesEvent() throws {
        let blue = Routine(name: "Morning")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet")
        context.insert(med)
        let item = RoutineItem(quantity: 1.0, medication: med, routine: blue)
        context.insert(item)
        try context.save()

        try MedicationService.removeFromRoutine(item, in: context)

        #expect(med.routineItems?.isEmpty == true)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "Morning · 1 tablet")
        #expect(event.newValue == "")
    }

    @Test
    func testMoveToRoutinePreservesQuantityAndWritesOldNewEvent() throws {
        let morning = Routine(name: "Morning")
        let afternoon = Routine(name: "Afternoon")
        context.insert(morning); context.insert(afternoon)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        let item = RoutineItem(quantity: 1.5, medication: med, routine: morning)
        context.insert(item)
        try context.save()

        try MedicationService.moveToRoutine(item, to: afternoon, in: context)

        #expect(item.routine?.name == "Afternoon")
        #expect(item.quantity == 1.5)
        #expect(DoseAllocation.allocated(med) == 1.5)
        let event = try #require((med.changeEvents ?? []).first {
            $0.eventType == MedChangeType.scheduleChanged.rawValue })
        #expect(event.oldValue == "Morning · 1.5 tablet")
        #expect(event.newValue == "Afternoon · 1.5 tablet")
    }

    @Test
    func testMoveToRoutineRejectsDuplicateMembership() throws {
        let morning = Routine(name: "Morning")
        let afternoon = Routine(name: "Afternoon")
        context.insert(morning); context.insert(afternoon)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        let inMorning = RoutineItem(quantity: 1.0, medication: med, routine: morning)
        let inAfternoon = RoutineItem(quantity: 1.0, medication: med, routine: afternoon)
        context.insert(inMorning); context.insert(inAfternoon)
        try context.save()

        #expect(throws: MembershipError.alreadyInRoutine) {
            try MedicationService.moveToRoutine(inMorning, to: afternoon, in: context)
        }
    }

    @Test
    func testDeleteRoutineThrowsWhenActiveMedicationPresent() throws {
        let routine = Routine(name: "Morning")
        context.insert(routine)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet", isActive: true)
        context.insert(med)
        context.insert(RoutineItem(quantity: 1.0, medication: med, routine: routine))
        try context.save()

        #expect(throws: RoutineError.hasActiveMedications) {
            try MedicationService.deleteRoutine(routine, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<Routine>()).count == 1)
    }

    @Test
    func testDeleteRoutineSucceedsWhenNoActiveMedsAndPreservesDoseLogSnapshots() throws {
        let routine = Routine(name: "Morning", colorHex: "#3B82F6")
        context.insert(routine)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, form: "tablet", isActive: false)
        context.insert(med)
        let item = RoutineItem(quantity: 1.0, medication: med, routine: routine)
        context.insert(item)
        let log = DoseLog(scheduledDate: .now, takenAt: .now, status: .taken, quantity: 1.0,
                          snapshotMedName: "Metoprolol", snapshotStrength: "30 mg",
                          snapshotStrengthValue: 30, snapshotStrengthUnit: "mg",
                          medication: med, routineItem: item)
        context.insert(log)
        try context.save()

        try MedicationService.deleteRoutine(routine, in: context)

        #expect(try context.fetch(FetchDescriptor<Routine>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RoutineItem>()).isEmpty)   // cascade removed the join row
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.routineItem == nil)                              // link nullified
        #expect(logs.first?.snapshotMedName == "Metoprolol")              // snapshot survives
    }

    @Test
    func testAddToRoutineRejectsDuplicateMembership() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)
        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: 2.0, form: "tablet")
        context.insert(med)
        try context.save()

        try MedicationService.addToRoutine(med, blue, quantity: 1.0, in: context)

        #expect(throws: MembershipError.alreadyInRoutine) {
            try MedicationService.addToRoutine(med, blue, quantity: 1.0, in: context)
        }
    }
}

