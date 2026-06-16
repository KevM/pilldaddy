import Foundation
import SwiftData

@Model
final class PillColor {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = ""
    
    @Relationship(deleteRule: .nullify, inverse: \Pill.pillColor)
    var pills: [Pill]? = []
    
    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.pills = []
    }
}
