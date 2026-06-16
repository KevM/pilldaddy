import Foundation
import SwiftData

@Model
final class Pill {
    var id: UUID = UUID()
    var name: String = ""
    var dosage: String = ""
    var scheduleTime: Date = Date()
    var isActive: Bool = true
    var createdAt: Date = Date()
    
    var pillColor: PillColor? = nil
    
    // API Meta Properties
    var ndc: String? = nil
    var splSetId: String? = nil
    var imageUrlString: String? = nil
    var imprint: String? = nil
    var shapeName: String? = nil
    var colorDescription: String? = nil
    
    @Relationship(deleteRule: .nullify, inverse: \DoseLog.pill)
    var doseLogs: [DoseLog]? = []
    
    @Relationship(deleteRule: .nullify, inverse: \DoseChangeLog.pill)
    var doseChangeLogs: [DoseChangeLog]? = []
    
    init(
        id: UUID = UUID(),
        name: String = "",
        dosage: String = "",
        scheduleTime: Date = Date(),
        isActive: Bool = true,
        ndc: String? = nil,
        splSetId: String? = nil,
        imageUrlString: String? = nil,
        imprint: String? = nil,
        shapeName: String? = nil,
        colorDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.scheduleTime = scheduleTime
        self.isActive = isActive
        self.createdAt = Date()
        self.pillColor = nil
        self.doseLogs = []
        self.doseChangeLogs = []
        
        self.ndc = ndc
        self.splSetId = splSetId
        self.imageUrlString = imageUrlString
        self.imprint = imprint
        self.shapeName = shapeName
        self.colorDescription = colorDescription
    }
}
