import Foundation
import SwiftData

enum DoseLogServiceError: Error, Equatable {
    case noteRequired
}

/// Owns every dose-logging mutation as a single atomic save. The idempotency
/// (one row per med/slot/day), fill-not-overwrite, and required-note rules live
/// here so they're unit-testable independent of the UI.
@MainActor
enum DoseLogService {

    // MARK: - Scheduled batches

    /// Marks the given items taken for the batch's slot on `day` (the fill set the
    /// confirm sheet computed). Items not passed are left untouched. Optional note.
    static func logBatchTaken(
        _ batch: Batch, on day: Date, items: [BatchItem],
        takenAt: Date, note: String, in context: ModelContext
    ) {
        for item in items {
            upsert(item: item, on: day, status: .taken, takenAt: takenAt, note: note, in: context)
        }
        try? context.save()
    }

    /// Upserts a single med's row for its slot on `day`. A skip requires a note.
    static func logMed(
        _ item: BatchItem, on day: Date, status: DoseStatus,
        takenAt: Date?, note: String, in context: ModelContext
    ) throws {
        if status == .skipped { try requireNote(note) }
        upsert(item: item, on: day, status: status, takenAt: takenAt, note: note, in: context)
        try context.save()
    }

    /// Deletes the slot row for one med on `day` (back to unlogged).
    static func revert(_ item: BatchItem, on day: Date, in context: ModelContext) {
        if let log = existingLog(for: item, on: day) { context.delete(log) }
        try? context.save()
    }

    /// Deletes the slot rows for all given items on `day` (back to unlogged).
    static func revertBatch(_ batch: Batch, on day: Date, items: [BatchItem], in context: ModelContext) {
        for item in items {
            if let log = existingLog(for: item, on: day) { context.delete(log) }
        }
        try? context.save()
    }

    /// Writes a `missed` row for the item's slot on `day` only if nothing is logged
    /// there yet (never overwrites a taken/skipped dose). Idempotent.
    static func materializeMissed(_ item: BatchItem, on day: Date, in context: ModelContext) {
        guard existingLog(for: item, on: day) == nil else { return }
        upsert(item: item, on: day, status: .missed, takenAt: nil, note: "", in: context)
        try? context.save()
    }

    // MARK: - PRN

    /// Records a new ad-hoc PRN dose (never upserted — each is its own dose).
    @discardableResult
    static func logPRN(
        _ med: Medication, takenAt: Date, quantity: Double,
        note: String, in context: ModelContext
    ) -> DoseLog {
        let log = DoseLog(
            scheduledDate: takenAt, takenAt: takenAt, status: .taken,
            quantity: quantity, notes: note,
            snapshotMedName: med.name, snapshotStrength: med.strengthDescription,
            snapshotStrengthValue: med.strengthValue, snapshotStrengthUnit: med.strengthUnit,
            snapshotBatchColorHex: "", medication: med, batchItem: nil)
        context.insert(log)
        try? context.save()
        return log
    }

    /// Removes a single PRN dose.
    static func deletePRNLog(_ log: DoseLog, in context: ModelContext) {
        context.delete(log)
        try? context.save()
    }

    // MARK: - Internal

    @discardableResult
    private static func upsert(
        item: BatchItem, on day: Date, status: DoseStatus,
        takenAt: Date?, note: String, in context: ModelContext
    ) -> DoseLog {
        let log: DoseLog
        if let existing = existingLog(for: item, on: day) {
            log = existing
        } else {
            log = DoseLog(medication: item.medication, batchItem: item)
            context.insert(log)
        }
        let slot = item.batch.map { DayQuery.slotDate(for: $0, on: day) }
            ?? Calendar.current.startOfDay(for: day)
        log.scheduledDate = slot
        log.status = status.rawValue
        log.takenAt = (status == .taken) ? (takenAt ?? .now) : nil
        log.quantity = item.quantity
        log.notes = note
        log.snapshotMedName = item.medication?.name ?? ""
        log.snapshotStrength = item.medication?.strengthDescription ?? ""
        log.snapshotStrengthValue = item.medication?.strengthValue ?? 0
        log.snapshotStrengthUnit = item.medication?.strengthUnit ?? "mg"
        log.snapshotBatchColorHex = item.batch?.colorHex ?? ""
        return log
    }

    private static func existingLog(for item: BatchItem, on day: Date) -> DoseLog? {
        let cal = Calendar.current
        return (item.doseLogs ?? []).first { cal.isDate($0.scheduledDate, inSameDayAs: day) }
    }

    private static func requireNote(_ note: String) throws {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DoseLogServiceError.noteRequired
        }
    }
}
