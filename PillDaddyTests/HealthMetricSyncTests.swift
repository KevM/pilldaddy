import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct HealthMetricSyncTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let writer: FakeHealthKitWriter

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
        self.writer = FakeHealthKitWriter()
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

    @Test
    func testResyncSyncsOnlyAuthorizedKinds() async throws {
        writer.authorizationByKind = [.weight: .authorized, .bloodPressure: .denied]
        insertPending(.weight, 180)
        insertPending(.weight, 181)
        insertPending(.bloodPressure, 150, secondary: 95)
        try context.save()

        let synced = await HealthMetricService.resyncPending(writer: writer, in: context)
        #expect(synced == 2)

        let all = try context.fetch(FetchDescriptor<HealthMetric>())
        #expect(all.filter { $0.metricKind == .weight }.allSatisfy { $0.healthKitSynced })
        let bp = try #require(all.first { $0.metricKind == .bloodPressure })
        #expect(!bp.healthKitSynced)
        #expect(writer.savedBatches.count == 2)
    }

    @Test
    func testResyncIsIdempotentAndDoesNotDuplicate() async throws {
        writer.authorizationByKind = [.weight: .authorized]
        insertPending(.weight, 180)
        try context.save()

        let first = await HealthMetricService.resyncPending(writer: writer, in: context)
        #expect(first == 1)
        let second = await HealthMetricService.resyncPending(writer: writer, in: context)
        #expect(second == 0)
        #expect(writer.savedBatches.count == 1)   // no duplicate save
    }

    @Test
    func testPendingCount() throws {
        insertPending(.weight, 180)
        insertPending(.water, 16)
        try context.save()
        #expect(HealthMetricService.pendingCount(in: context) == 2)
    }

    @Test
    func testOverallAuthorizationStates() {
        writer.authorizationByKind = allAuthorized()
        #expect(HealthMetricService.overallAuthorization(writer: writer) == .authorized)

        writer.authorizationByKind = Dictionary(uniqueKeysWithValues:
            MetricKind.allCases.map { ($0, .denied) })
        #expect(HealthMetricService.overallAuthorization(writer: writer) == .denied)

        writer.authorizationByKind = Dictionary(uniqueKeysWithValues:
            MetricKind.allCases.map { ($0, .notDetermined) })
        #expect(HealthMetricService.overallAuthorization(writer: writer) == .notDetermined)

        writer.authorizationByKind = allAuthorized(except: [.bloodPressure])
        #expect(HealthMetricService.overallAuthorization(writer: writer) == .partial)
    }

    @Test
    func testUnavailableWriterReportsUnavailable() {
        writer.isHealthDataAvailable = false
        #expect(HealthMetricService.overallAuthorization(writer: writer) == .unavailable)
    }
}

