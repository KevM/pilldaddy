import Foundation
import SwiftData

@Model
final class Medication {
    var name: String = ""
    var strength: String = ""          // free text, e.g. "30mg"
    var form: String = "tablet"
    var generalNotes: String = ""
    var isActive: Bool = true
    var isPRN: Bool = false            // as-needed; no batch memberships
    var createdAt: Date = Date.now
    var discontinuedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \BatchItem.medication)
    var batchItems: [BatchItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.medication)
    var doseLogs: [DoseLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \MedicationChangeEvent.medication)
    var changeEvents: [MedicationChangeEvent]? = []

    /// The medication that replaced this one (swap continuity chain).
    var successor: Medication? = nil

    @Relationship(inverse: \Medication.successor)
    var predecessor: Medication? = nil

    init(name: String = "", strength: String = "", form: String = "tablet",
         generalNotes: String = "", isActive: Bool = true, isPRN: Bool = false,
         createdAt: Date = .now, discontinuedAt: Date? = nil) {
        self.name = name
        self.strength = strength
        self.form = form
        self.generalNotes = generalNotes
        self.isActive = isActive
        self.isPRN = isPRN
        self.createdAt = createdAt
        self.discontinuedAt = discontinuedAt
    }
}
