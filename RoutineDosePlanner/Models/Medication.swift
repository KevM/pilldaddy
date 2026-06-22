import Foundation
import SwiftData

@Model
final class Medication {
    var name: String = ""
    var strengthValue: Double = 0          // amount per unit, e.g. 30
    var strengthUnit: String = "mg"        // label only; never converted across units
    var dailyDoseTarget: Double = 1        // prescribed units per full dosing day (count)
    var weekdayDoseTargets: [Double]? = nil // nil = uniform (use dailyDoseTarget); else 7 values, index = weekday-1
    var form: String = "tablet"
    var generalNotes: String = ""
    var isActive: Bool = true
    var isPRN: Bool = false                // as-needed; no routine memberships
    var createdAt: Date = Date.now
    var discontinuedAt: Date? = nil
    var uuid: UUID = UUID()
    var rxNormCode: String = ""            // RXCUI; empty until RxNorm lookup is wired up

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.medication)
    var routineItems: [RoutineItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \DoseLog.medication)
    var doseLogs: [DoseLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \MedicationChangeEvent.medication)
    var changeEvents: [MedicationChangeEvent]? = []

    /// The medication that replaced this one (swap continuity chain).
    var successor: Medication? = nil

    @Relationship(inverse: \Medication.successor)
    var predecessor: Medication? = nil

    /// Display-only formatted strength, e.g. "30 mg". Never used for math.
    var strengthDescription: String { "\(DoseFormat.qty(strengthValue)) \(strengthUnit)" }

    /// Prescribed target for a Calendar weekday (1=Sun … 7=Sat).
    func target(forWeekday wd: Int) -> Double {
        WeekdayDoseTargets.resolve(forWeekday: wd, daily: dailyDoseTarget, perWeekday: weekdayDoseTargets)
    }

    /// True when the prescription differs across days (drives UI disclosure).
    var hasVariableSchedule: Bool { weekdayDoseTargets != nil }

    init(name: String = "", strengthValue: Double = 0, strengthUnit: String = "mg",
         dailyDoseTarget: Double = 1, form: String = "tablet",
         generalNotes: String = "", isActive: Bool = true, isPRN: Bool = false,
         createdAt: Date = .now, discontinuedAt: Date? = nil,
         uuid: UUID = UUID(), rxNormCode: String = "") {
        self.name = name
        self.strengthValue = strengthValue
        self.strengthUnit = strengthUnit
        self.dailyDoseTarget = dailyDoseTarget
        self.form = form
        self.generalNotes = generalNotes
        self.isActive = isActive
        self.isPRN = isPRN
        self.createdAt = createdAt
        self.discontinuedAt = discontinuedAt
        self.uuid = uuid
        self.rxNormCode = rxNormCode
    }
}
