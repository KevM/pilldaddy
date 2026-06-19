import Foundation
import SwiftData

enum MedicationServiceError: Error, Equatable {
    case reasonRequired
}

/// Owns every multi-step medication mutation as a single atomic save, so the
/// "caregiver can't get it wrong" guarantees live in one unit-testable place.
@MainActor
enum MedicationService {

    /// Creates a medication, its batch memberships (skipped for PRN), and an
    /// `added` change event. Reason is optional on add.
    @discardableResult
    static func addMedication(
        name: String, strength: String, form: String,
        isPRN: Bool, notes: String,
        placements: [(batch: Batch, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) -> Medication {
        let med = Medication(name: name, strength: strength, form: form,
                             generalNotes: notes, isPRN: isPRN)
        context.insert(med)

        if !isPRN {
            for placement in placements {
                context.insert(BatchItem(quantity: placement.quantity,
                                         medication: med, batch: placement.batch))
            }
        }

        context.insert(MedicationChangeEvent(type: .added, reasoning: reason, medication: med))
        try? context.save()
        return med
    }

    /// Changes strength and/or per-batch quantities on the same medication and
    /// records a `doseChanged` event with an old→new summary. Reason required.
    static func changeDose(
        _ med: Medication,
        newStrength: String,
        newQuantities: [(item: BatchItem, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)
        let oldSummary = doseSummary(med)
        med.strength = newStrength
        for change in newQuantities {
            change.item.quantity = change.quantity
        }
        let newSummary = doseSummary(med)
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: reason,
            oldValue: oldSummary, newValue: newSummary, medication: med))
        try context.save()
     }

    /// Updates a single membership's instructions and records an
    /// `instructionsChanged` event. Reason required.
    static func changeInstructions(
        _ item: BatchItem,
        newInstructions: String,
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)
        let old = item.instructionsOverride
        item.instructionsOverride = newInstructions
        context.insert(MedicationChangeEvent(
            type: .instructionsChanged, reasoning: reason,
            oldValue: old, newValue: newInstructions, medication: item.medication))
        try context.save()
    }

    /// Atomically swaps one drug for a new one: create the replacement, optionally
    /// inherit the old drug's batch memberships, link `successor`, discontinue the
    /// old drug, and write a `swapped` event (old) + `added` event (new). Reason required.
    @discardableResult
    static func swap(
        _ oldMed: Medication,
        newName: String, newStrength: String, newForm: String,
        inheritSchedule: Bool,
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        try requireReason(reason)

        let newMed = Medication(name: newName, strength: newStrength, form: newForm)
        context.insert(newMed)

        if inheritSchedule {
            for item in oldMed.batchItems ?? [] {
                context.insert(BatchItem(
                    quantity: item.quantity,
                    instructionsOverride: item.instructionsOverride,
                    medication: newMed, batch: item.batch))
            }
        }

        let oldDescription = "\(oldMed.name) \(oldMed.strength)"
        oldMed.successor = newMed
        oldMed.isActive = false
        oldMed.discontinuedAt = .now

        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: reason,
            oldValue: oldDescription, newValue: "\(newName) \(newStrength)",
            medication: oldMed))
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: reason, medication: newMed))

        try context.save()
        return newMed
    }

     // MARK: - Internal helpers

    /// Human-readable summary of a med's current dose, deterministic (sorted by batch name).
    static func doseSummary(_ med: Medication) -> String {
        let parts = (med.batchItems ?? [])
            .sorted { ($0.batch?.name ?? "") < ($1.batch?.name ?? "") }
            .map { "\($0.batch?.name ?? "?") \(DoseFormat.qty($0.quantity))" }
        let schedule = parts.isEmpty ? "PRN" : parts.joined(separator: ", ")
        return "\(med.strength) — \(schedule)"
    }

    static func requireReason(_ reason: String) throws {
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MedicationServiceError.reasonRequired
        }
    }
}
