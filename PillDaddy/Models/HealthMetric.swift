import Foundation
import SwiftData

/// One health reading. Generic across all metric kinds; `secondaryValue` exists
/// only so Blood Pressure (120/80) is a single row. Written one-way to Apple Health.
@Model
final class HealthMetric {
    var kind: String = MetricKind.weight.rawValue   // MetricKind raw value
    var value: Double = 0                            // primary (systolic for BP)
    var secondaryValue: Double? = nil                // diastolic for BP; nil otherwise
    var unit: String = ""                            // display unit, e.g. "lb"
    var recordedAt: Date = Date.now
    var note: String = ""
    var healthKitSynced: Bool = false                // written to Apple Health yet?
    var healthKitSampleUUID: String? = nil           // traceability / dedup

    var metricKind: MetricKind { MetricKind(rawValue: kind) ?? .weight }

    init(kind: MetricKind = .weight, value: Double = 0, secondaryValue: Double? = nil,
         unit: String = "", recordedAt: Date = .now, note: String = "",
         healthKitSynced: Bool = false, healthKitSampleUUID: String? = nil) {
        self.kind = kind.rawValue
        self.value = value
        self.secondaryValue = secondaryValue
        self.unit = unit
        self.recordedAt = recordedAt
        self.note = note
        self.healthKitSynced = healthKitSynced
        self.healthKitSampleUUID = healthKitSampleUUID
    }
}
