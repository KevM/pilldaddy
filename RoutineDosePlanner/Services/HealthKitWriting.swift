import Foundation
import HealthKit

enum HealthKitWriteError: Error { case unavailable }

/// Per-metric Apple Health *share* (write) authorization. Readable because the app is
/// write-only — HealthKit only hides *read* authorization.
enum HealthShareAuthorization: Equatable { case authorized, denied, notDetermined }

/// Abstraction over the real HKHealthStore so capture flows are testable with a fake.
protocol HealthKitWriting {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async
    func save(_ objects: [HKObject]) async throws
    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization
}

/// Real implementation. Write-only — we never request read access (keeps the
/// iCloud-storage exemption; see spec "App Store / TestFlight considerations").
final class LiveHealthKitWriter: HealthKitWriting {
    private let store = HKHealthStore()
    private var didRequest = false

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.bodyMass), HKQuantityType(.dietaryWater),
        HKQuantityType(.heartRate), HKQuantityType(.oxygenSaturation),
        HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic),
    ]

    /// HK object types whose *share* authorization status represents this metric kind.
    ///
    /// Blood pressure is special: the user grants a single grouped "Blood Pressure" toggle,
    /// and HealthKit records that grant on the **correlation** type — the systolic/diastolic
    /// component quantity types keep reporting `.notDetermined` (confirmed on-device). So we
    /// must read the correlation type, not the components, or status reads as "Not set".
    static func authorizationTypes(for kind: MetricKind) -> [HKObjectType] {
        switch kind {
        case .weight: return [HKQuantityType(.bodyMass)]
        case .water: return [HKQuantityType(.dietaryWater)]
        case .pulse: return [HKQuantityType(.heartRate)]
        case .oxygenSaturation: return [HKQuantityType(.oxygenSaturation)]
        case .bloodPressure:
            return [HKCorrelationType(.bloodPressure)]
        }
    }

    /// Aggregate raw HK statuses: denied if any is denied; authorized only if all are
    /// authorized; otherwise not-determined.
    static func aggregate(_ statuses: [HKAuthorizationStatus]) -> HealthShareAuthorization {
        if statuses.contains(.sharingDenied) { return .denied }
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .sharingAuthorized }) { return .authorized }
        return .notDetermined
    }

    func requestAuthorizationIfNeeded() async {
        guard isHealthDataAvailable, !didRequest else { return }
        didRequest = true
        try? await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    func save(_ objects: [HKObject]) async throws {
        guard isHealthDataAvailable else { throw HealthKitWriteError.unavailable }
        try await store.save(objects)
    }

    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization {
        guard isHealthDataAvailable else { return .notDetermined }
        let statuses = Self.authorizationTypes(for: kind).map { store.authorizationStatus(for: $0) }
        return Self.aggregate(statuses)
    }
}
