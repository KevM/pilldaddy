import Foundation
import SwiftData

@Model
final class BatchItem {
    var quantity: Double = 1.0              // fractions allowed (0.5)
    var instructionsOverride: String = ""

    var medication: Medication? = nil
    var batch: Batch? = nil

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.batchItem)
    var doseLogs: [DoseLog]? = []

    init(quantity: Double = 1.0, instructionsOverride: String = "",
         medication: Medication? = nil, batch: Batch? = nil) {
        self.quantity = quantity
        self.instructionsOverride = instructionsOverride
        self.medication = medication
        self.batch = batch
    }
}
