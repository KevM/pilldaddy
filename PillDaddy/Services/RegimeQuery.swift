import Foundation
import SwiftData

/// Read helpers that assemble the *active* daily regime from the model.
@MainActor
enum RegimeQuery {

    /// A batch paired with its active, non-PRN memberships (sorted by med name).
    struct BatchGroup: Identifiable {
        let batch: Batch
        let items: [BatchItem]
        var id: PersistentIdentifier { batch.persistentModelID }
    }

    /// All batches (ordered by sortOrder then time), each with its active meds only.
    static func activeBatchGroups(in context: ModelContext) throws -> [BatchGroup] {
        let batches = try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]))
        return batches.map { batch in
            let items = (batch.items ?? [])
                .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
                .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
            return BatchGroup(batch: batch, items: items)
        }
    }

    /// Active PRN (as-needed) medications, sorted by name.
    static func activePRNMeds(in context: ModelContext) throws -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive && $0.isPRN },
            sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }
}
