import Foundation
import SwiftData

@Model
final class DoseLog {
    var scheduledDate: Date = Date.now      // the day/slot this dose belonged to
    var takenAt: Date? = nil
    var status: String = DoseStatus.taken.rawValue
    var quantity: Double = 1.0
    var notes: String = ""
    var uuid: UUID = UUID()

    // snapshot fields, frozen at log time
    var snapshotMedName: String = ""
    var snapshotStrength: String = ""
    var snapshotStrengthValue: Double = 0
    var snapshotStrengthUnit: String = "mg"
    var isPRN: Bool = false                  // frozen at log time; true only for ad-hoc PRN doses

    var medication: Medication? = nil
    var batchItem: BatchItem? = nil          // nil for PRN logs

    init(scheduledDate: Date = .now, takenAt: Date? = nil, status: DoseStatus = .taken,
         quantity: Double = 1.0, notes: String = "", uuid: UUID = UUID(),
         snapshotMedName: String = "", snapshotStrength: String = "",
         snapshotStrengthValue: Double = 0, snapshotStrengthUnit: String = "mg",
         isPRN: Bool = false,
         medication: Medication? = nil, batchItem: BatchItem? = nil) {
        self.scheduledDate = scheduledDate
        self.takenAt = takenAt
        self.status = status.rawValue
        self.quantity = quantity
        self.notes = notes
        self.uuid = uuid
        self.snapshotMedName = snapshotMedName
        self.snapshotStrength = snapshotStrength
        self.snapshotStrengthValue = snapshotStrengthValue
        self.snapshotStrengthUnit = snapshotStrengthUnit
        self.isPRN = isPRN
        self.medication = medication
        self.batchItem = batchItem
    }
}
