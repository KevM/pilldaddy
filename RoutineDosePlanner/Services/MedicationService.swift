import Foundation
import SwiftData

enum MedicationServiceError: Error, Equatable {
    case reasonRequired
}

enum DoseAllocationError: Error, Equatable {
    case exceedsDailyTarget
}

enum MembershipError: Error, Equatable {
    case alreadyInRoutine
}

enum RoutineError: Error, Equatable {
    case hasActiveMedications
}

/// Owns every multi-step medication mutation as a single atomic save, so the
/// "caregiver can't get it wrong" guarantees live in one unit-testable place.
@MainActor
enum MedicationService {

    /// Creates a medication, its routine memberships (skipped for PRN), and an
    /// `added` change event. Reason is optional on add.
    @discardableResult
    static func addMedication(
        name: String, strengthValue: Double, strengthUnit: String, form: String,
        isPRN: Bool, notes: String, dailyDoseTarget: Double = 1,
        weekdayDoseTargets: [Double]? = nil,
        placements: [(routine: Routine, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws -> Medication {
        if !isPRN {
            if DoseAllocation.placementsOverTarget(
                daily: dailyDoseTarget, perWeekday: weekdayDoseTargets, placements: placements) {
                throw DoseAllocationError.exceedsDailyTarget
            }
        }
        let med = Medication(name: name, strengthValue: strengthValue, strengthUnit: strengthUnit,
                             dailyDoseTarget: dailyDoseTarget, weekdayDoseTargets: weekdayDoseTargets, form: form,
                             generalNotes: notes, isPRN: isPRN)
        context.insert(med)

        if !isPRN {
            for placement in placements {
                context.insert(RoutineItem(quantity: placement.quantity,
                                         medication: med, routine: placement.routine))
            }
        }

        context.insert(MedicationChangeEvent(type: .added, reasoning: reason, medication: med))
        try context.save()
        return med
    }

    /// Changes strength and/or the full per-routine allocation on the same medication
    /// and records a `doseChanged` event with an old→new summary. `placements` is the
    /// complete desired set: existing memberships absent from it are removed, new ones
    /// are created, matching ones are updated. Reason required.
    static func changeDose(
        _ med: Medication,
        newStrengthValue: Double, newStrengthUnit: String,
        newDailyDoseTarget: Double,
        newWeekdayDoseTargets: [Double]? = nil,
        placements: [(routine: Routine, quantity: Double)],
        reason: String,
        in context: ModelContext
    ) throws {
        try requireReason(reason)

        if DoseAllocation.placementsOverTarget(
            daily: newDailyDoseTarget, perWeekday: newWeekdayDoseTargets, placements: placements) {
            throw DoseAllocationError.exceedsDailyTarget
        }

        let oldSummary = doseSummary(med)
        med.strengthValue = newStrengthValue
        med.strengthUnit = newStrengthUnit
        med.dailyDoseTarget = newDailyDoseTarget
        med.weekdayDoseTargets = newWeekdayDoseTargets

        // Reconcile memberships against the desired placement set.
        let desired = Dictionary(uniqueKeysWithValues:
            placements.map { ($0.routine.persistentModelID, $0.quantity) })
        var existingRoutineIDs = Set<PersistentIdentifier>()
        for item in med.routineItems ?? [] {
            guard let routineID = item.routine?.persistentModelID else { continue }
            if let qty = desired[routineID] {
                item.quantity = qty
                existingRoutineIDs.insert(routineID)
            } else {
                context.delete(item)
            }
        }
        for placement in placements where !existingRoutineIDs.contains(placement.routine.persistentModelID) {
            context.insert(RoutineItem(quantity: placement.quantity,
                                       medication: med, routine: placement.routine))
        }

        let newSummary = doseSummary(med)
        context.insert(MedicationChangeEvent(
            type: .doseChanged, reasoning: reason,
            oldValue: oldSummary, newValue: newSummary, medication: med))
        try context.save()
    }

    /// Adds a medication to a routine with a chosen quantity, rejecting anything
    /// that would push total allocation past the daily-dose target. Initial
    /// placement needs no reason.
    static func addToRoutine(
        _ med: Medication, _ routine: Routine, quantity: Double,
        in context: ModelContext
    ) throws {
        let medID = med.persistentModelID
        let duplicate = (routine.items ?? []).contains { $0.medication?.persistentModelID == medID }
        if duplicate { throw MembershipError.alreadyInRoutine }

        if DoseAllocation.adding(quantity, to: routine, exceedsTargetFor: med) {
            throw DoseAllocationError.exceedsDailyTarget
        }
        let item = RoutineItem(quantity: quantity, medication: med, routine: routine)
        context.insert(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: "", newValue: membershipDescription(item), medication: med))
        try context.save()
    }

    /// Removes a medication's routine membership and records a `scheduleChanged`
    /// event documenting what left. No reason required.
    static func removeFromRoutine(_ item: RoutineItem, in context: ModelContext) throws {
        let med = item.medication
        let old = membershipDescription(item)
        context.delete(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: old, newValue: "", medication: med))
        try context.save()
    }

    /// Relocates a membership to another routine, preserving its quantity, and
    /// records a `scheduleChanged` event. Because the quantity is relocated (not
    /// added), total allocation is unchanged, so no cap check is needed. Throws
    /// if the target routine already contains this medication.
    static func moveToRoutine(_ item: RoutineItem, to routine: Routine, in context: ModelContext) throws {
        let medID = item.medication?.persistentModelID
        let duplicate = (routine.items ?? []).contains { $0.medication?.persistentModelID == medID }
        if duplicate { throw MembershipError.alreadyInRoutine }

        guard let med = item.medication else { return }
        if DoseAllocation.moving(item, to: routine) {
            throw DoseAllocationError.exceedsDailyTarget
        }
        let old = membershipDescription(item)
        item.routine = routine
        let new = membershipDescription(item)
        context.insert(MedicationChangeEvent(
            type: .scheduleChanged, reasoning: "",
            oldValue: old, newValue: new, medication: med))
        try context.save()
    }

    /// Hard-deletes a routine, allowed only when no active (non-PRN) medication is
    /// a member. Remaining (discontinued-med) join rows cascade away; dose-log
    /// snapshots survive intact.
    static func deleteRoutine(_ routine: Routine, in context: ModelContext) throws {
        let hasActive = (routine.items ?? []).contains {
            ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false)
        }
        if hasActive { throw RoutineError.hasActiveMedications }
        context.delete(routine)
        try context.save()
    }

    /// Updates a single membership's instructions and records an
    /// `instructionsChanged` event. Reason required.
    static func changeInstructions(
        _ item: RoutineItem,
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
    /// inherit the old drug's routine memberships, link `successor`, discontinue the
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
            for item in oldMed.routineItems ?? [] {
                context.insert(RoutineItem(
                    quantity: item.quantity,
                    instructionsOverride: item.instructionsOverride,
                    medication: newMed, routine: item.routine))
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

    /// Restores a discontinued medication to the active routines (its memberships
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
    static func membershipDescription(_ item: RoutineItem) -> String {
        let routine = item.routine?.name ?? "?"
        let form = item.medication?.form ?? ""
        let desc = "\(routine) · \(DoseFormat.qty(item.quantity)) \(form)"
        return desc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Human-readable summary of a med's current dose, deterministic (sorted by routine name).
    static func doseSummary(_ med: Medication) -> String {
        let parts = (med.routineItems ?? [])
            .sorted { ($0.routine?.name ?? "") < ($1.routine?.name ?? "") }
            .map { "\($0.routine?.name ?? "?") \(DoseFormat.qty($0.quantity))" }
        let schedule = parts.isEmpty ? "PRN" : parts.joined(separator: ", ")
        return "\(med.strengthDescription) — \(schedule)"
    }

    static func requireReason(_ reason: String) throws {
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MedicationServiceError.reasonRequired
        }
    }
}
