import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct HealthMetricServiceTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let writer: FakeHealthKitWriter

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
        self.writer = FakeHealthKitWriter()
    }

    private func metrics() throws -> [HealthMetric] {
        try context.fetch(FetchDescriptor<HealthMetric>())
    }

    @Test
    func testRecordScalarPersistsAndSyncsOnSuccess() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 180, note: "",
                                                   writer: writer, in: context)
        let m = try #require(try metrics().first)
        #expect(m.metricKind == .weight)
        #expect(m.unit == "lb")
        #expect(m.healthKitSynced)
        #expect(m.healthKitSampleUUID != nil)
        #expect(writer.savedBatches.count == 1)
    }

    @Test
    func testFailedWriteLeavesRowUnsynced() async throws {
        writer.shouldThrow = true
        try await HealthMetricService.recordScalar(kind: .water, value: 16, note: "",
                                                   writer: writer, in: context)
        let m = try #require(try metrics().first)
        #expect(!m.healthKitSynced)        // capture still succeeded
        #expect(m.healthKitSampleUUID == nil)
    }

    @Test
    func testImplausibleScalarThrowsAndPersistsNothing() async throws {
        await #expect(throws: HealthMetricService.ServiceError.implausible) {
            try await HealthMetricService.recordScalar(kind: .oxygenSaturation, value: 130,
                                                       note: "", writer: writer, in: context)
        }
        #expect(try metrics().count == 0)
    }

    @Test
    func testRecordVitalsWritesOnlyPresentFields() async throws {
        try await HealthMetricService.recordVitals(systolic: 120, diastolic: 80, pulse: 68,
                                                   spo2: nil, note: "", writer: writer, in: context)
        let all = try metrics()
        #expect(all.count == 2)             // BP row + pulse row, no SpO₂
        let bp = try #require(all.first { $0.metricKind == .bloodPressure })
        #expect(bp.value == 120)
        #expect(bp.secondaryValue == 80)
        #expect(all.contains { $0.metricKind == .pulse })
        #expect(!all.contains { $0.metricKind == .oxygenSaturation })
    }

    @Test
    func testVitalsBloodPressureBothOrNeither() async throws {
        await #expect(throws: HealthMetricService.ServiceError.bloodPressureIncomplete) {
            try await HealthMetricService.recordVitals(systolic: 120, diastolic: nil, pulse: nil,
                                                       spo2: nil, note: "", writer: writer, in: context)
        }
        #expect(try metrics().count == 0)
    }

    @Test
    func testDeleteRemovesRow() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 180, note: "",
                                                   writer: writer, in: context)
        let m = try #require(try metrics().first)
        HealthMetricService.delete(m, in: context)
        #expect(try metrics().count == 0)
    }

    @Test
    func testCueContextLoadsPreviousWeightAndTodayWaterTotal() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 178, note: "",
                                                   writer: writer, in: context)
        let wctx = HealthMetricService.cueContext(for: .weight, in: context)
        #expect(wctx.previousValue == 178)
        #expect(wctx.previousDate != nil)

        try await HealthMetricService.recordScalar(kind: .water, value: 20, note: "",
                                                   writer: writer, in: context)
        try await HealthMetricService.recordScalar(kind: .water, value: 30, note: "",
                                                   writer: writer, in: context)
        let actx = HealthMetricService.cueContext(for: .water, in: context)
        #expect(actx.todayTotal == 50)
    }
}

