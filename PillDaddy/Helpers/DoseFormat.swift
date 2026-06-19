import Foundation

/// Formats a dose quantity for display: whole numbers drop the decimal ("1"),
/// fractions keep it ("0.5").
enum DoseFormat {
    static func qty(_ q: Double) -> String {
        q == q.rounded() ? String(Int(q)) : String(q)
    }
}
