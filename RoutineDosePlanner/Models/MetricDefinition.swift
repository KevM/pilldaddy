import Foundation

/// Advisory severity for a reading → green / yellow / red. Never blocks saving.
enum MetricCue {
    case normal, caution, alert
    var severity: Int { self == .alert ? 2 : (self == .caution ? 1 : 0) }
    static func worst(_ a: MetricCue, _ b: MetricCue) -> MetricCue { a.severity >= b.severity ? a : b }
}

enum MetricArchetype { case scalar, paired }
enum CaptureGroup { case scalar, vitals }

/// History passed to contextual cues (weight Δ, water daily total). Absolute cues ignore it.
struct CueContext {
    let previousValue: Double?
    let previousDate: Date?
    let todayTotal: Double?
    let now: Date
    static let empty = CueContext(previousValue: nil, previousDate: nil, todayTotal: nil, now: .now)
}

/// Everything the UI and writer need for one metric kind. Held in MetricRegistry.
struct MetricDefinition {
    let kind: MetricKind
    let displayName: String
    let archetype: MetricArchetype
    let captureGroup: CaptureGroup
    let unit: String                 // display unit: "lb", "oz", "mmHg", "bpm", "%"
    let secondaryUnit: String?       // "mmHg" for BP; nil otherwise
    let plausibleRange: ClosedRange<Double>          // outside = reject save
    let secondaryPlausibleRange: ClosedRange<Double>?
    let quickAdd: [Double]?          // [8,12,16] for water; nil otherwise
    let customAddDefault: Double?    // 32 for water; nil otherwise
    let cue: (_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue
    let healthAppBreadcrumb: String  // where to find it in the Health app
}
