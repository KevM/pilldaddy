import Foundation
import SwiftData

@Model
final class DoseLog {
    var id: UUID = UUID()
    var pillName: String = ""
    var dosage: String = ""
    var colorHex: String = ""
    var timestamp: Date = Date()
    var status: String = "taken" // "taken", "skipped"
    var notes: String? = nil
    
    var pill: Pill? = nil
    
    init(id: UUID = UUID(), pillName: String = "", dosage: String = "", colorHex: String = "", timestamp: Date = Date(), status: String = "taken", notes: String? = nil) {
        self.id = id
        self.pillName = pillName
        self.dosage = dosage
        self.colorHex = colorHex
        self.timestamp = timestamp
        self.status = status
        self.notes = notes
        self.pill = nil
    }
}
