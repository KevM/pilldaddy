import Foundation

/// The single source of per-metric facts and advisory cue thresholds.
enum MetricRegistry {
    static func definition(for kind: MetricKind) -> MetricDefinition {
        switch kind {
        case .weight:
            return MetricDefinition(
                kind: .weight, displayName: "Weight", archetype: .scalar, captureGroup: .scalar,
                unit: "lb", secondaryUnit: nil, plausibleRange: 40...660, secondaryPlausibleRange: nil,
                quickAdd: nil, customAddDefault: nil, cue: weightCue,
                healthAppBreadcrumb: "Browse › Body Measurements › Weight")
        case .water:
            return MetricDefinition(
                kind: .water, displayName: "Water", archetype: .scalar, captureGroup: .scalar,
                unit: "oz", secondaryUnit: nil, plausibleRange: 0...256, secondaryPlausibleRange: nil,
                quickAdd: [8, 12, 16], customAddDefault: 32, cue: waterCue,
                healthAppBreadcrumb: "Browse › Nutrition › Water")
        case .bloodPressure:
            return MetricDefinition(
                kind: .bloodPressure, displayName: "Blood Pressure", archetype: .paired, captureGroup: .vitals,
                unit: "mmHg", secondaryUnit: "mmHg", plausibleRange: 50...300, secondaryPlausibleRange: 20...200,
                quickAdd: nil, customAddDefault: nil, cue: bloodPressureCue,
                healthAppBreadcrumb: "Browse › Heart › Blood Pressure")
        case .pulse:
            return MetricDefinition(
                kind: .pulse, displayName: "Pulse", archetype: .scalar, captureGroup: .vitals,
                unit: "bpm", secondaryUnit: nil, plausibleRange: 20...300, secondaryPlausibleRange: nil,
                quickAdd: nil, customAddDefault: nil, cue: pulseCue,
                healthAppBreadcrumb: "Browse › Heart › Heart Rate")
        case .oxygenSaturation:
            return MetricDefinition(
                kind: .oxygenSaturation, displayName: "Oxygen (SpO₂)", archetype: .scalar, captureGroup: .vitals,
                unit: "%", secondaryUnit: nil, plausibleRange: 50...100, secondaryPlausibleRange: nil,
                quickAdd: nil, customAddDefault: nil, cue: oxygenCue,
                healthAppBreadcrumb: "Browse › Respiratory › Blood Oxygen")
        }
    }

    static var all: [MetricDefinition] { MetricKind.allCases.map(definition(for:)) }

    // MARK: - Cue logic (thresholds: see spec "Validation & clinical cues")

    private static func systolicCue(_ s: Double) -> MetricCue {
        if s < 80 || s >= 180 { return .alert }
        if s < 90 || s >= 120 { return .caution }
        return .normal
    }
    private static func diastolicCue(_ d: Double) -> MetricCue {
        if d < 40 || d >= 120 { return .alert }
        if d < 60 || d >= 80 { return .caution }
        return .normal
    }
    private static func bloodPressureCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        guard let dia = secondary else { return systolicCue(value) }
        return MetricCue.worst(systolicCue(value), diastolicCue(dia))
    }
    private static func pulseCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        if value < 50 || value > 120 { return .alert }
        if value < 60 || value > 100 { return .caution }
        return .normal
    }
    private static func oxygenCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        if value <= 90 { return .alert }
        if value < 95 { return .caution }
        return .normal
    }
    private static func waterCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        let perEntry: MetricCue = value > 64 ? .alert : (value > 32 ? .caution : .normal)
        let total = (ctx.todayTotal ?? 0) + value
        let daily: MetricCue = total > 135 ? .alert : (total > 100 ? .caution : .normal)
        return MetricCue.worst(perEntry, daily)
    }
    private static func weightCue(_ value: Double, _ secondary: Double?, _ ctx: CueContext) -> MetricCue {
        guard let prev = ctx.previousValue, let prevDate = ctx.previousDate else { return .normal }
        let delta = abs(value - prev)
        let days = max(0, ctx.now.timeIntervalSince(prevDate) / 86_400)
        if days <= 1 && delta >= 2 { return .alert }
        if days <= 7 && delta >= 5 { return .alert }
        if days <= 7 && delta >= 3 { return .caution }
        return .normal
    }
}
