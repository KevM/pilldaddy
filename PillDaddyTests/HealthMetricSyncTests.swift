import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class HealthMetricSyncTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var writer: FakeHealthKitWriter!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
        writer = FakeHealthKitWriter()
    }
    override func tearDown() async throws {
        writer = nil; context = nil; container = nil
        try await super.tearDown()
    }

    private func insertPending(_ kind: MetricKind, _ value: Double, secondary: Double? = nil) {
        let unit = MetricRegistry.definition(for: kind).unit
        context.insert(HealthMetric(kind: kind, value: value, secondaryValue: secondary, unit: unit))
    }

    private func allAuthorized(except denied: Set<MetricKind> = []) -> [MetricKind: HealthShareAuthorization] {
        Dictionary(uniqueKeysWithValues: MetricKind.allCases.map {
            ($0, denied.contains($0) ? .denied : .authorized)
        })
    }

    func testResyncSyncsOnlyAuthorizedKinds() async throws {
        writer.authorizationByKind = [.weight: .authorized, .bloodPressure: .denied]
        insertPending(.weight, 180)
        insertPending(.weight, 181)
        insertPending(.bloodPressure, 150, secondary: 95)
        try context.save()

        let synced = await HealthMetricService.resyncPending(writer: writer, in: context)
        XCTAssertEqual(synced, 2)

        let all = try context.fetch(FetchDescriptor<HealthMetric>())
        XCTAssertTrue(all.filter { $0.metricKind == .weight }.allSatisfy { $0.healthKitSynced })
        let bp = try XCTUnwrap(all.first { $0.metricKind == .bloodPressure })
        XCTAssertFalse(bp.healthKitSynced)
        XCTAssertEqual(writer.savedBatches.count, 2)
    }

    func testResyncIsIdempotentAndDoesNotDuplicate() async throws {
        writer.authorizationByKind = [.weight: .authorized]
        insertPending(.weight, 180)
        try context.save()

        let first = await HealthMetricService.resyncPending(writer: writer, in: context)
        XCTAssertEqual(first, 1)
        let second = await HealthMetricService.resyncPending(writer: writer, in: context)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(writer.savedBatches.count, 1)   // no duplicate save
    }

    func testPendingCount() throws {
        insertPending(.weight, 180)
        insertPending(.water, 16)
        try context.save()
        XCTAssertEqual(HealthMetricService.pendingCount(in: context), 2)
    }

    func testOverallAuthorizationStates() {
        writer.authorizationByKind = allAuthorized()
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .authorized)

        writer.authorizationByKind = Dictionary(uniqueKeysWithValues:
            MetricKind.allCases.map { ($0, .denied) })
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .denied)

        writer.authorizationByKind = Dictionary(uniqueKeysWithValues:
            MetricKind.allCases.map { ($0, .notDetermined) })
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .notDetermined)

        writer.authorizationByKind = allAuthorized(except: [.bloodPressure])
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .partial)
    }

    func testUnavailableWriterReportsUnavailable() {
        writer.isHealthDataAvailable = false
        XCTAssertEqual(HealthMetricService.overallAuthorization(writer: writer), .unavailable)
    }
}
