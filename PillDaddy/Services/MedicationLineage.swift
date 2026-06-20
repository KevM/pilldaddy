import Foundation
import SwiftData

/// Pure helpers for reading a medication's *therapy line* — the chain of drugs
/// connected by swaps (`predecessor`/`successor`) — and merging their change
/// events into one continuous, lineage-aware story. No model or schema changes;
/// traverses in-memory relationships only.
@MainActor
enum MedicationLineage {

    /// The whole therapy line that `med` belongs to, oldest → newest. Walks
    /// `predecessor` back to the root, then `successor` forward to the tip.
    /// Cycle-guarded: every med is visited at most once.
    static func ordered(from med: Medication) -> [Medication] {
        // Walk back to the root.
        var root = med
        var backVisited: Set<PersistentIdentifier> = [med.persistentModelID]
        while let prev = root.predecessor, !backVisited.contains(prev.persistentModelID) {
            backVisited.insert(prev.persistentModelID)
            root = prev
        }
        // Walk forward from the root, collecting the line.
        var line: [Medication] = []
        var seen: Set<PersistentIdentifier> = []
        var node: Medication? = root
        while let current = node, !seen.contains(current.persistentModelID) {
            seen.insert(current.persistentModelID)
            line.append(current)
            node = current.successor
        }
        return line
    }
}
