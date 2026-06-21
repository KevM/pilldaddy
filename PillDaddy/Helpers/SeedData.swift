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
        let blue = Routine(name: "Blue", colorHex: "#3B82F6",
                         timeOfDay: time(9, 0), mealRelation: .withFood)
        let green = Routine(name: "Green", colorHex: "#10B981",
                          timeOfDay: time(19, 0), mealRelation: .afterFood)
        // An early batch (07:00) that is overdue by mid-morning so the missed/Live
        // Activity paths are exercisable from seed.
        let dawn = Routine(name: "Dawn", colorHex: "#8B5CF6",
                         timeOfDay: time(7, 0), mealRelation: .beforeFood)
        context.insert(blue)
        context.insert(green)
        context.insert(dawn)

        // Scheduled meds
        let metoprolol = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.5)
        let vitaminD = Medication(name: "Vitamin D", strengthValue: 1000, strengthUnit: "IU", dailyDoseTarget: 2.0, form: "capsule")
        context.insert(metoprolol)
        context.insert(vitaminD)
        let metoprololBlue = RoutineItem(quantity: 1.0, medication: metoprolol, routine: blue)
        let vitaminDBlue = RoutineItem(quantity: 1.0, medication: vitaminD, routine: blue)
        context.insert(metoprololBlue)
        context.insert(RoutineItem(quantity: 0.5, medication: metoprolol, routine: green))
        context.insert(vitaminDBlue)
        context.insert(RoutineItem(quantity: 1.0, medication: vitaminD, routine: dawn))

        // PRN med
        let acetaminophen = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg", dailyDoseTarget: 1.0, isPRN: true)
        context.insert(acetaminophen)

        // Continuity chain: Atenolol was the original beta blocker, swapped out
        // for Metoprolol. The journal therefore spans both drugs so the
        // lineage timeline has a real cross-drug story to show.
        func daysAgo(_ days: Int) -> Date {
            cal.date(byAdding: .day, value: -days, to: .now) ?? .now
        }

        let atenolol = Medication(name: "Atenolol", strengthValue: 25, strengthUnit: "mg", dailyDoseTarget: 1.0,
                                  isActive: false, discontinuedAt: daysAgo(100))
        context.insert(atenolol)
        atenolol.successor = metoprolol   // links predecessor on Metoprolol too

        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(150), type: .added,
            reasoning: "Started for hypertension after the January check-up",
            medication: atenolol))
        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(100), type: .swapped,
            reasoning: "Persistent cold hands; switched to a more selective blocker",
            oldValue: "Atenolol 25 mg", newValue: "Metoprolol 30 mg",
            medication: atenolol))
        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(30), type: .doseChanged,
            reasoning: "Reduced evening dose after dizziness",
            oldValue: "1 tablet", newValue: "½ tablet", medication: metoprolol))
        context.insert(MedicationChangeEvent(
            timestamp: daysAgo(5), type: .note,
            reasoning: "Cardiologist confirmed dose at June visit — keep as is",
            medication: metoprolol))

        // Today's logging: Blue batch partially logged (Metoprolol taken, Vitamin D
        // skipped), one PRN dose taken. Green batch left pending.
        let blueSlot = DayQuery.slotDate(for: blue, on: .now)
        context.insert(DoseLog(
            scheduledDate: blueSlot, takenAt: time(9, 5), status: .taken, quantity: 1.0,
            snapshotMedName: metoprolol.name, snapshotStrength: metoprolol.strengthDescription,
            medication: metoprolol, routineItem: metoprololBlue))
        context.insert(DoseLog(
            scheduledDate: blueSlot, status: .skipped, quantity: 1.0, notes: "Held — low appetite",
            snapshotMedName: vitaminD.name, snapshotStrength: vitaminD.strengthDescription,
            medication: vitaminD, routineItem: vitaminDBlue))
        context.insert(DoseLog(
            scheduledDate: time(14, 30), takenAt: time(14, 30), status: .taken, quantity: 1.0,
            snapshotMedName: acetaminophen.name, snapshotStrength: acetaminophen.strengthDescription,
            medication: acetaminophen, routineItem: nil))

        // Health metrics — a few recent readings so the Health tab is exercisable.
        // Local-only; never written to Apple Health by the seed.
        context.insert(HealthMetric(kind: .weight, value: 178, unit: "lb", recordedAt: daysAgo(2)))
        context.insert(HealthMetric(kind: .weight, value: 182, unit: "lb", recordedAt: .now))
        context.insert(HealthMetric(kind: .water, value: 16, unit: "oz", recordedAt: .now))
        context.insert(HealthMetric(kind: .bloodPressure, value: 152, secondaryValue: 96,
                                    unit: "mmHg", recordedAt: .now))
        context.insert(HealthMetric(kind: .pulse, value: 68, unit: "bpm", recordedAt: .now))
        context.insert(HealthMetric(kind: .oxygenSaturation, value: 93, unit: "%", recordedAt: .now))
    }
}

