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

    private func sampleTypes(for kind: MetricKind) -> [HKSampleType] {
        switch kind {
        case .weight: return [HKQuantityType(.bodyMass)]
        case .water: return [HKQuantityType(.dietaryWater)]
        case .pulse: return [HKQuantityType(.heartRate)]
        case .oxygenSaturation: return [HKQuantityType(.oxygenSaturation)]
        case .bloodPressure:
            return [HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
        }
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

    /// A kind is authorized only if every underlying share type is; denied if any is.
    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization {
        guard isHealthDataAvailable else { return .notDetermined }
        let statuses = sampleTypes(for: kind).map { store.authorizationStatus(for: $0) }
        if statuses.contains(.sharingDenied) { return .denied }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) { return .authorized }
        return .notDetermined
    }
}
