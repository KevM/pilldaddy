import Foundation
import HealthKit
@testable import PillDaddy

/// Configurable HealthKitWriting fake for service tests.
final class FakeHealthKitWriter: HealthKitWriting {
    var isHealthDataAvailable = true
    var shouldThrow = false
    private(set) var savedBatches: [[HKObject]] = []
    private(set) var authRequested = false

    func requestAuthorizationIfNeeded() async { authRequested = true }

    func save(_ objects: [HKObject]) async throws {
        if shouldThrow { throw HealthKitWriteError.unavailable }
        savedBatches.append(objects)
    }
}
