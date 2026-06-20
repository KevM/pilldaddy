import Foundation

/// The single place value+unit strings are produced, so switching display units
/// (localization) is a contained change. See spec "Localization readiness".
enum MetricFormatter {
    static func string(_ value: Double, unit: String) -> String {
        let n = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(n) \(unit)"
    }

    static func bloodPressure(_ systolic: Double, _ diastolic: Double) -> String {
        "\(Int(systolic))/\(Int(diastolic))"
    }
}
