import Foundation
import SwiftData

/// One change event positioned within a therapy line, carrying the context the
/// timeline UI needs to render it (which drug it belongs to, whether that drug
/// is the one the timeline was opened from, and the swap destination name).
struct LineageEvent: Identifiable {
    let event: MedicationChangeEvent
    let owningMed: Medication
    let isAnchor: Bool
    let successorName: String?

    var id: PersistentIdentifier { event.persistentModelID }
}

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

    /// Every change event across the whole line, newest first, with these
    /// presentation rules applied:
    ///   • `added` events on swap-born meds (those with a predecessor) are
    ///     dropped — the preceding "Swapped to …" row is the med's origin.
    /// `isAnchor` is true for events on `med` itself; `successorName` carries the
    /// next drug's name so swap rows can read "Swapped to {name}".
    static func events(from med: Medication) -> [LineageEvent] {
        let line = ordered(from: med)
        let anchorID = med.persistentModelID
        var result: [LineageEvent] = []
        for owner in line {
            for event in owner.changeEvents ?? [] {
                if event.eventType == MedChangeType.added.rawValue && owner.predecessor != nil {
                    continue
                }
                result.append(LineageEvent(
                    event: event,
                    owningMed: owner,
                    isAnchor: owner.persistentModelID == anchorID,
                    successorName: owner.successor?.name))
            }
        }
        return result.sorted { $0.event.timestamp > $1.event.timestamp }
    }
}
