import Foundation

/// Pure helpers for the per-weekday dose-target representation. Centralizes the
/// nil-means-uniform fallback and the collapse/expand used by editors so the rule
/// lives in exactly one place.
enum WeekdayDoseTargets {
    private static let tolerance = 0.0001

    /// Resolved target for a weekday (1=Sun…7=Sat): the per-weekday value when set,
    /// otherwise the uniform `daily` value.
    static func resolve(forWeekday wd: Int, daily: Double, perWeekday: [Double]?) -> Double {
        perWeekday?[wd - 1] ?? daily
    }

    /// A 7-value array for editing: the stored per-weekday values, or `daily`
    /// repeated when uniform.
    static func expand(daily: Double, perWeekday: [Double]?) -> [Double] {
        perWeekday ?? Array(repeating: daily, count: 7)
    }

    /// Collapse an edited 7-value array back to storage form: if every value is
    /// equal, return uniform (perWeekday = nil); otherwise keep the array. The
    /// returned `daily` is the first value (used as the uniform/fallback target).
    static func collapse(_ values: [Double]) -> (daily: Double, perWeekday: [Double]?) {
        precondition(values.count == 7, "weekday targets must have 7 values")
        let first = values[0]
        let uniform = values.allSatisfy { abs($0 - first) <= tolerance }
        return uniform ? (first, nil) : (first, values)
    }
}
