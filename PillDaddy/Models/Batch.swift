import SwiftData

@Model
final class Batch {
    @Relationship(deleteRule: .cascade, inverse: \BatchItem.batch)
    var items: [BatchItem]? = []
    
    init() {}
}
