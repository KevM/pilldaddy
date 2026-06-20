import Foundation
import HealthKit

enum HealthKitWriteError: Error { case unavailable }

/// Abstraction over the real HKHealthStore so capture flows are testable with a fake.
protocol HealthKitWriting {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorizationIfNeeded() async
    func save(_ objects: [HKObject]) async throws
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

    func requestAuthorizationIfNeeded() async {
        guard isHealthDataAvailable, !didRequest else { return }
        didRequest = true
        try? await store.requestAuthorization(toShare: shareTypes, read: [])
    }

    func save(_ objects: [HKObject]) async throws {
        guard isHealthDataAvailable else { throw HealthKitWriteError.unavailable }
        try await store.save(objects)
    }
}
