import SwiftData

@Model
final class DoseLog {
    var medication: Medication? = nil
    var batchItem: BatchItem? = nil
    init() {}
}
