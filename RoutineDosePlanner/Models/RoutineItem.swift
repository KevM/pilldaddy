import Foundation
import SwiftData

@Model
final class RoutineItem {
    var quantity: Double = 1.0              // fractions allowed (0.5)
    var instructionsOverride: String = ""

    var medication: Medication? = nil
    var routine: Routine? = nil

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.routineItem)
    var doseLogs: [DoseLog]? = []

    init(quantity: Double = 1.0, instructionsOverride: String = "",
         medication: Medication? = nil, routine: Routine? = nil) {
        self.quantity = quantity
        self.instructionsOverride = instructionsOverride
        self.medication = medication
        self.routine = routine
    }
}
