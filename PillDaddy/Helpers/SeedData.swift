import Foundation
import SwiftData

/// Loads a realistic test regime into an empty store so later sessions can be
/// exercised without manual setup. No-op if any Medication already exists.
enum SeedData {
    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        guard existing.isEmpty else { return }

        let cal = Calendar.current
        func time(_ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }

        // Batches
        let blue = Batch(name: "Blue", colorHex: "#3B82F6",
                         timeOfDay: time(9, 0), mealRelation: .withFood, sortOrder: 0)
        let green = Batch(name: "Green", colorHex: "#10B981",
                          timeOfDay: time(19, 0), mealRelation: .afterFood, sortOrder: 1)
        // An early batch (07:00) that is overdue by mid-morning so the missed/Live
        // Activity paths are exercisable from seed.
        let dawn = Batch(name: "Dawn", colorHex: "#8B5CF6",
                         timeOfDay: time(7, 0), mealRelation: .beforeFood, sortOrder: 2)
        context.insert(blue)
        context.insert(green)
        context.insert(dawn)

        // Scheduled meds
        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
        let vitaminD = Medication(name: "Vitamin D", strength: "1000 IU", form: "capsule")
        context.insert(metoprolol)
        context.insert(vitaminD)
        let metoprololBlue = BatchItem(quantity: 1.0, medication: metoprolol, batch: blue)
        let vitaminDBlue = BatchItem(quantity: 1.0, medication: vitaminD, batch: blue)
        context.insert(metoprololBlue)
        context.insert(BatchItem(quantity: 0.5, medication: metoprolol, batch: green))
        context.insert(vitaminDBlue)
        context.insert(BatchItem(quantity: 1.0, medication: vitaminD, batch: dawn))

        // PRN med
        let acetaminophen = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(acetaminophen)

        // A bit of journal history on Metoprolol
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: "Started for hypertension", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))

        // Today's logging: Blue batch partially logged (Metoprolol taken, Vitamin D
        // skipped), one PRN dose taken. Green batch left pending.
        let blueSlot = DayQuery.slotDate(for: blue, on: .now)
        context.insert(DoseLog(
            scheduledDate: blueSlot, takenAt: time(9, 5), status: .taken, quantity: 1.0,
            snapshotMedName: metoprolol.name, snapshotStrength: metoprolol.strength,
            snapshotBatchColorHex: blue.colorHex,
            medication: metoprolol, batchItem: metoprololBlue))
        context.insert(DoseLog(
            scheduledDate: blueSlot, status: .skipped, quantity: 1.0, notes: "Held — low appetite",
            snapshotMedName: vitaminD.name, snapshotStrength: vitaminD.strength,
            snapshotBatchColorHex: blue.colorHex,
            medication: vitaminD, batchItem: vitaminDBlue))
        context.insert(DoseLog(
            scheduledDate: time(14, 30), takenAt: time(14, 30), status: .taken, quantity: 1.0,
            snapshotMedName: acetaminophen.name, snapshotStrength: acetaminophen.strength,
            medication: acetaminophen, batchItem: nil))
    }
}

