import Foundation
import SwiftData

@Model
final class DoseChangeLog {
    var id: UUID = UUID()
    var pillName: String = ""
    var oldDosage: String = ""
    var newDosage: String = ""
    var timestamp: Date = Date()
    var reason: String = ""
    
    var pill: Pill? = nil
    
    init(id: UUID = UUID(), pillName: String = "", oldDosage: String = "", newDosage: String = "", timestamp: Date = Date(), reason: String = "") {
        self.id = id
        self.pillName = pillName
        self.oldDosage = oldDosage
        self.newDosage = newDosage
        self.timestamp = timestamp
        self.reason = reason
        self.pill = nil
    }
}
