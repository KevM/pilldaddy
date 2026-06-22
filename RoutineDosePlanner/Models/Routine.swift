import Foundation
import SwiftData

@Model
final class Routine {
    var name: String = ""
    var colorHex: String = "#3B82F6"
    var timeOfDay: Date = Date.now          // only the clock-time component is meaningful
    var mealRelation: String = MealRelation.none.rawValue
    var recurrenceKind: String = RecurrenceKind.daily.rawValue
    var weekdays: [Int]? = nil              // 1...7 when recurrenceKind == "weekdays"
    var uuid: UUID = UUID()

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
    var items: [RoutineItem]? = []

    /// Calendar weekdays (1=Sun…7=Sat) this routine fires on. Daily ⇒ all 7;
    /// weekdays ⇒ its configured list, sorted. Single source of recurrence truth.
    var firingWeekdays: [Int] {
        switch RecurrenceKind(rawValue: recurrenceKind) ?? .daily {
        case .daily: return [1, 2, 3, 4, 5, 6, 7]
        case .weekdays: return (weekdays ?? []).sorted()
        }
    }

    init(name: String = "", colorHex: String = "#3B82F6", timeOfDay: Date = .now,
         mealRelation: MealRelation = .none, recurrenceKind: RecurrenceKind = .daily,
         weekdays: [Int]? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.timeOfDay = timeOfDay
        self.mealRelation = mealRelation.rawValue
        self.recurrenceKind = recurrenceKind.rawValue
        self.weekdays = weekdays
    }
}
