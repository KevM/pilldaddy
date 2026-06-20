import Foundation
import HealthKit

/// Pure mapping from a HealthMetric to the HealthKit object(s) to save.
/// Display value → HK sample; SpO₂ converts % → fraction. No store, no auth.
enum HealthSampleMapper {
    static func map(_ metric: HealthMetric) -> [HKObject] {
        let date = metric.recordedAt
        switch metric.metricKind {
        case .weight:
            return [quantity(.bodyMass, .pound(), metric.value, date)]
        case .water:
            return [quantity(.dietaryWater, .fluidOunceUS(), metric.value, date)]
        case .pulse:
            return [quantity(.heartRate, HKUnit.count().unitDivided(by: .minute()), metric.value, date)]
        case .oxygenSaturation:
            return [quantity(.oxygenSaturation, .percent(), metric.value / 100.0, date)]
        case .bloodPressure:
            let sys = quantity(.bloodPressureSystolic, .millimeterOfMercury(), metric.value, date)
            let dia = quantity(.bloodPressureDiastolic, .millimeterOfMercury(), metric.secondaryValue ?? 0, date)
            let type = HKCorrelationType(.bloodPressure)
            return [HKCorrelation(type: type, start: date, end: date, objects: [sys, dia])]
        }
    }

    private static func quantity(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit,
                                 _ value: Double, _ date: Date) -> HKQuantitySample {
        HKQuantitySample(type: HKQuantityType(id),
                         quantity: HKQuantity(unit: unit, doubleValue: value),
                         start: date, end: date)
    }
}
