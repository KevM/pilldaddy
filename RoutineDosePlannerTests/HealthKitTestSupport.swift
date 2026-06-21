import Foundation
import HealthKit
@testable import RoutineDosePlanner

/// Configurable HealthKitWriting fake for service tests.
final class FakeHealthKitWriter: HealthKitWriting {
    var isHealthDataAvailable = true
    var shouldThrow = false
    /// Per-kind authorization; unset kinds default to `.authorized` so existing
    /// capture tests (which expect saves to succeed) keep passing.
    var authorizationByKind: [MetricKind: HealthShareAuthorization] = [:]
    private(set) var savedBatches: [[HKObject]] = []
    private(set) var authRequested = false

    func requestAuthorizationIfNeeded() async { authRequested = true }

    func save(_ objects: [HKObject]) async throws {
        if shouldThrow { throw HealthKitWriteError.unavailable }
        savedBatches.append(objects)
    }

    func authorizationStatus(for kind: MetricKind) -> HealthShareAuthorization {
        authorizationByKind[kind] ?? .authorized
    }
}
