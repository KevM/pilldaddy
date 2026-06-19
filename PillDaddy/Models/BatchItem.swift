import SwiftData

@Model
final class BatchItem {
    var medication: Medication? = nil
    var batch: Batch? = nil
    
    @Relationship(deleteRule: .nullify, inverse: \DoseLog.batchItem)
    var doseLogs: [DoseLog]? = []
    
    init() {}
}
