import Foundation
import SwiftData

@Model
final class Batch {
    var name: String = ""
    var colorHex: String = "#3B82F6"
    var timeOfDay: Date = Date.now          // only the clock-time component is meaningful
    var mealRelation: String = MealRelation.none.rawValue
    var recurrenceKind: String = RecurrenceKind.daily.rawValue
    var weekdays: [Int]? = nil              // 1...7 when recurrenceKind == "weekdays"
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \BatchItem.batch)
    var items: [BatchItem]? = []

    init(name: String = "", colorHex: String = "#3B82F6", timeOfDay: Date = .now,
         mealRelation: MealRelation = .none, recurrenceKind: RecurrenceKind = .daily,
         weekdays: [Int]? = nil, sortOrder: Int = 0) {
        self.name = name
        self.colorHex = colorHex
        self.timeOfDay = timeOfDay
        self.mealRelation = mealRelation.rawValue
        self.recurrenceKind = recurrenceKind.rawValue
        self.weekdays = weekdays
        self.sortOrder = sortOrder
    }
}
