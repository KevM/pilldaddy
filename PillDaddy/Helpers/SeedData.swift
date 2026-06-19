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
        context.insert(blue)
        context.insert(green)

        // Scheduled meds
        let metoprolol = Medication(name: "Metoprolol", strength: "30mg")
        let vitaminD = Medication(name: "Vitamin D", strength: "1000 IU", form: "capsule")
        context.insert(metoprolol)
        context.insert(vitaminD)
        context.insert(BatchItem(quantity: 1.0, medication: metoprolol, batch: blue))
        context.insert(BatchItem(quantity: 0.5, medication: metoprolol, batch: green))
        context.insert(BatchItem(quantity: 1.0, medication: vitaminD, batch: blue))

        // PRN med
        let acetaminophen = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(acetaminophen)

        // A bit of journal history on Metoprolol
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: "Started for hypertension", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))
    }
}
