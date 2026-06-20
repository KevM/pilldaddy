import Foundation
import SwiftData

enum MedicationServiceError: Error, Equatable {
    case reasonRequired
}

enum DoseAllocationError: Error, Equatable {
    case exceedsDailyTarget
}

enum MembershipError: Error, Equatable {
    case alreadyInBatch
}

/// Owns every multi-step medication mutation as a single atomic save, so the
/// "caregiver can't get it wrong" guarantees live in one unit-testable place.
@MainActor
enum MedicationService {

    /// Creates a medication, its batch memberships (skipped for PRN), and an
    /// `added` change event. Reason is optional on add.
    @discardableResult
    static func addMedication(
        name: String, strengthValue: Double, strengthUnit: String, form: String,
        isPRN: Bool, notes: String, dailyDoseTarget: Double = 1,
        placements: [(batch: Batch, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        if !isPRN {
            let total = placements.reduce(0) { $0 + $1.quantity }
            if DoseAllocation.isOverTarget(allocated: total, target: dailyDoseTarget) {
                throw DoseAllocationError.exceedsDailyTarget
            }
        }
        let med = Medication(name: name, strengthValue: strengthValue, strengthUnit: strengthUnit,
                             dailyDoseTarget: dailyDoseTarget, form: form,
                             generalNotes: notes, isPRN: isPRN)
        context.insert(med)

        if !isPRN {
            for placement in placements {
                context.insert(BatchItem(quantity: placement.quantity,
                                         medication: med, batch: placement.batch))
            }
        }

        context.insert(MedicationChangeEvent(type: .added, reasoning: reason, medication: med))
        try context.save()
        return med
    }

    /// Changes strength and/or per-batch quantities on the same medication and
    /// records a `doseChanged` event with an old→new summary. Reason required.
    static func changeDose(
        _ med: Medication,
        newStrengthValue: Double, newStrengthUnit: String,
        newDailyDoseTarget: Double,
        newQuantities: [(item: BatchItem, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)

        // Prospective total = sum of quantities, using the new value where provided.
        let overrides = Dictionary(uniqueKeysWithValues:
            newQuantities.map { ($0.item.persistentModelID, $0.quantity) })
        let prospective = (med.batchItems ?? []).reduce(0.0) { sum, item in
            sum + (overrides[item.persistentModelID] ?? item.quantity)
        }
        if DoseAllocation.isOverTarget(allocated: prospective, target: newDailyDoseTarget) {
            throw DoseAllocationError.exceedsDailyTarget
        }

        let oldSummary = doseSummary(med)
        med.strengthValue = newStrengthValue
        med.strengthUnit = newStrengthUnit
        med.dailyDoseTarget = newDailyDoseTarget
        for change in newQuantities {
            change.item.quantity = change.quantity
        }
        let newSummary = doseSummary(med)
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: reason,
            oldValue: oldSummary, newValue: newSummary, medication: med))
        try context.save()
     }

    /// Adds a medication to a batch with a chosen quantity, rejecting anything
    /// that would push total allocation past the daily-dose target. Initial
    /// placement needs no reason.
    static func addToBatch(
        _ med: Medication, _ batch: Batch, quantity: Double,
        in context: ModelContext
    ) throws {
        if DoseAllocation.isOverTarget(allocated: DoseAllocation.allocated(med) + quantity, target: med.dailyDoseTarget) {
            throw DoseAllocationError.exceedsDailyTarget
        }
        let item = BatchItem(quantity: quantity, medication: med, batch: batch)
        context.insert(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: "", newValue: membershipDescription(item), medication: med))
        try context.save()
    }

    /// Removes a medication's batch membership and records a `scheduleChanged`
    /// event documenting what left. No reason required.
    static func removeFromBatch(_ item: BatchItem, in context: ModelContext) throws {
        let med = item.medication
        let old = membershipDescription(item)
        context.delete(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: old, newValue: "", medication: med))
        try context.save()
    }

    /// Relocates a membership to another batch, preserving its quantity, and
    /// records a `scheduleChanged` event. Because the quantity is relocated (not
    /// added), total allocation is unchanged, so no cap check is needed. Throws
    /// if the target batch already contains this medication.
    static func moveToBatch(_ item: BatchItem, to batch: Batch, in context: ModelContext) throws {
        let medID = item.medication?.persistentModelID
        let duplicate = (batch.items ?? []).contains { $0.medication?.persistentModelID == medID }
        if duplicate { throw MembershipError.alreadyInBatch }

        let med = item.medication
        let old = membershipDescription(item)
        item.batch = batch
        let new = membershipDescription(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: old, newValue: new, medication: med))
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
        newName: String, newStrengthValue: Double, newStrengthUnit: String, newForm: String,
        inheritSchedule: Bool,
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        try requireReason(reason)

        let newMed = Medication(name: newName, strengthValue: newStrengthValue, strengthUnit: newStrengthUnit, form: newForm)
        context.insert(newMed)

        if inheritSchedule {
            for item in oldMed.batchItems ?? [] {
                context.insert(BatchItem(
                    quantity: item.quantity,
                    instructionsOverride: item.instructionsOverride,
                    medication: newMed, batch: item.batch))
            }
        }

        let oldDescription = "\(oldMed.name) \(oldMed.strengthDescription)"
        oldMed.successor = newMed
        oldMed.isActive = false
        oldMed.discontinuedAt = .now

        context.insert(MedicationChangeEvent(
            type: .swapped, reasoning: reason,
            oldValue: oldDescription,
            newValue: "\(newName) \(DoseFormat.qty(newStrengthValue)) \(newStrengthUnit)",
            medication: oldMed))
        context.insert(MedicationChangeEvent(
            type: .added, reasoning: reason, medication: newMed))

        try context.save()
        return newMed
    }

    /// Marks a medication discontinued (keeps its memberships and history) and
    /// writes a `discontinued` event. Reason required.
    static func discontinue(_ med: Medication, reason: String, in context: ModelContext) throws {
        try requireReason(reason)
        med.isActive = false
        med.discontinuedAt = .now
        context.insert(MedicationChangeEvent(type: .discontinued, reasoning: reason, medication: med))
        try context.save()
    }

    /// Restores a discontinued medication to the active regime (its memberships
    /// reappear automatically) and writes a `reactivated` event. Reason required.
    static func reactivate(_ med: Medication, reason: String, in context: ModelContext) throws {
        try requireReason(reason)
        med.isActive = true
        med.discontinuedAt = nil
        context.insert(MedicationChangeEvent(type: .reactivated, reasoning: reason, medication: med))
        try context.save()
    }

    /// Appends a free-form retrospective note to a medication's journal as a
    /// `note` event. Note text is required (empty/whitespace rejected).
    static func addNote(_ med: Medication, text: String, in context: ModelContext) throws {
        try requireReason(text)
        context.insert(MedicationChangeEvent(type: .note, reasoning: text, medication: med))
        try context.save()
    }

     // MARK: - Internal helpers

    /// Human-readable membership description frozen into schedule-change events,
    /// e.g. "Morning · 1 tablet".
    static func membershipDescription(_ item: BatchItem) -> String {
        let batch = item.batch?.name ?? "?"
        let form = item.medication?.form ?? ""
        return "\(batch) · \(DoseFormat.qty(item.quantity)) \(form)"
    }

    /// Human-readable summary of a med's current dose, deterministic (sorted by batch name).
    static func doseSummary(_ med: Medication) -> String {
        let parts = (med.batchItems ?? [])
            .sorted { ($0.batch?.name ?? "") < ($1.batch?.name ?? "") }
            .map { "\($0.batch?.name ?? "?") \(DoseFormat.qty($0.quantity))" }
        let schedule = parts.isEmpty ? "PRN" : parts.joined(separator: ", ")
        return "\(med.strengthDescription) — \(schedule)"
    }

    static func requireReason(_ reason: String) throws {
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MedicationServiceError.reasonRequired
        }
    }
}
