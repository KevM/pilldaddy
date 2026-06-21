import Foundation
import SwiftData

/// Read helpers that assemble the *active* daily routines from the model.
@MainActor
enum RoutineQuery {

    /// A routine paired with its active, non-PRN memberships (sorted by med name).
    struct RoutineGroup: Identifiable {
        let routine: Routine
        let items: [RoutineItem]
        var id: PersistentIdentifier { routine.persistentModelID }
    }

    /// All routines (ordered by time of day), each with its active meds only.
    static func activeRoutineGroups(in context: ModelContext) throws -> [RoutineGroup] {
        let routines = try context.fetch(FetchDescriptor<Routine>(
            sortBy: [SortDescriptor(\.timeOfDay), SortDescriptor(\.uuid)]))
        return routines.map { routine in
            let items = (routine.items ?? [])
                .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
                .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
            return RoutineGroup(routine: routine, items: items)
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
