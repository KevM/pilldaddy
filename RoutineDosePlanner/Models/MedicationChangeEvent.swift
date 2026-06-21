import Foundation
import SwiftData

@Model
final class MedicationChangeEvent {
    var timestamp: Date = Date.now
    var eventType: String = MedChangeType.note.rawValue
    var reasoning: String = ""              // mandatory in UX for change/swap (not a DB constraint)
    var oldValue: String = ""
    var newValue: String = ""

    var medication: Medication? = nil

    init(timestamp: Date = .now, type: MedChangeType = .note, reasoning: String = "",
         oldValue: String = "", newValue: String = "", medication: Medication? = nil) {
        self.timestamp = timestamp
        self.eventType = type.rawValue
        self.reasoning = reasoning
        self.oldValue = oldValue
        self.newValue = newValue
        self.medication = medication
    }
}
