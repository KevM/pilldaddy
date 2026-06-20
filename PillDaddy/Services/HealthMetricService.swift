import Foundation
import SwiftData

/// Owns capture (persist-then-best-effort-write), deletion, and cue-context
/// assembly. Persist always succeeds locally; the HealthKit write is best-effort.
@MainActor
enum HealthMetricService {
    enum ServiceError: Error, Equatable { case implausible, bloodPressureIncomplete }

    static func recordScalar(kind: MetricKind, value: Double, note: String,
                             recordedAt: Date = .now,
                             writer: HealthKitWriting, in context: ModelContext) async throws {
        let def = MetricRegistry.definition(for: kind)
        guard def.plausibleRange.contains(value) else { throw ServiceError.implausible }
        let metric = HealthMetric(kind: kind, value: value, unit: def.unit,
                                  recordedAt: recordedAt, note: note)
        context.insert(metric)
        try? context.save()
        await commit(metric, writer: writer, in: context)
    }

    static func recordVitals(systolic: Double?, diastolic: Double?, pulse: Double?, spo2: Double?,
                             note: String, recordedAt: Date = .now,
                             writer: HealthKitWriting, in context: ModelContext) async throws {
        if (systolic == nil) != (diastolic == nil) { throw ServiceError.bloodPressureIncomplete }

        var rows: [HealthMetric] = []
        if let s = systolic, let d = diastolic {
            let def = MetricRegistry.definition(for: .bloodPressure)
            guard def.plausibleRange.contains(s),
                  def.secondaryPlausibleRange?.contains(d) ?? true else { throw ServiceError.implausible }
            rows.append(HealthMetric(kind: .bloodPressure, value: s, secondaryValue: d,
                                     unit: def.unit, recordedAt: recordedAt, note: note))
        }
        if let p = pulse {
            let def = MetricRegistry.definition(for: .pulse)
            guard def.plausibleRange.contains(p) else { throw ServiceError.implausible }
            rows.append(HealthMetric(kind: .pulse, value: p, unit: def.unit,
                                     recordedAt: recordedAt, note: note))
        }
        if let o = spo2 {
            let def = MetricRegistry.definition(for: .oxygenSaturation)
            guard def.plausibleRange.contains(o) else { throw ServiceError.implausible }
            rows.append(HealthMetric(kind: .oxygenSaturation, value: o, unit: def.unit,
                                     recordedAt: recordedAt, note: note))
        }

        rows.forEach { context.insert($0) }
        try? context.save()
        for row in rows { await commit(row, writer: writer, in: context) }
    }

    static func delete(_ metric: HealthMetric, in context: ModelContext) {
        context.delete(metric)
        try? context.save()
    }

    /// History for contextual cues: previous weight (weight Δ) or today's water total.
    static func cueContext(for kind: MetricKind, now: Date = .now,
                           in context: ModelContext) -> CueContext {
        switch kind {
        case .weight:
            let raw = MetricKind.weight.rawValue
            var fd = FetchDescriptor<HealthMetric>(
                predicate: #Predicate { $0.kind == raw },
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
            fd.fetchLimit = 1
            let prev = (try? context.fetch(fd))?.first
            return CueContext(previousValue: prev?.value, previousDate: prev?.recordedAt,
                              todayTotal: nil, now: now)
        case .water:
            let raw = MetricKind.water.rawValue
            let start = Calendar.current.startOfDay(for: now)
            let fd = FetchDescriptor<HealthMetric>(
                predicate: #Predicate { $0.kind == raw && $0.recordedAt >= start })
            let total = ((try? context.fetch(fd)) ?? []).reduce(0) { $0 + $1.value }
            return CueContext(previousValue: nil, previousDate: nil, todayTotal: total, now: now)
        default:
            return CueContext(previousValue: nil, previousDate: nil, todayTotal: nil, now: now)
        }
    }

    private static func commit(_ metric: HealthMetric, writer: HealthKitWriting,
                               in context: ModelContext) async {
        await writer.requestAuthorizationIfNeeded()
        let objects = HealthSampleMapper.map(metric)
        do {
            try await writer.save(objects)
            metric.healthKitSynced = true
            metric.healthKitSampleUUID = objects.first?.uuid.uuidString
            try? context.save()
        } catch {
            // Best-effort: leave the row unsynced (no retry in MVP).
        }
    }
}
