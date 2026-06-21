import SwiftData
import XCTest
@testable import RoutineDosePlanner

@MainActor
final class HealthMetricServiceTests: XCTestCase {
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

    private func metrics() throws -> [HealthMetric] {
        try context.fetch(FetchDescriptor<HealthMetric>())
    }

    func testRecordScalarPersistsAndSyncsOnSuccess() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 180, note: "",
                                                   writer: writer, in: context)
        let m = try XCTUnwrap(try metrics().first)
        XCTAssertEqual(m.metricKind, .weight)
        XCTAssertEqual(m.unit, "lb")
        XCTAssertTrue(m.healthKitSynced)
        XCTAssertNotNil(m.healthKitSampleUUID)
        XCTAssertEqual(writer.savedBatches.count, 1)
    }

    func testFailedWriteLeavesRowUnsynced() async throws {
        writer.shouldThrow = true
        try await HealthMetricService.recordScalar(kind: .water, value: 16, note: "",
                                                   writer: writer, in: context)
        let m = try XCTUnwrap(try metrics().first)
        XCTAssertFalse(m.healthKitSynced)        // capture still succeeded
        XCTAssertNil(m.healthKitSampleUUID)
    }

    func testImplausibleScalarThrowsAndPersistsNothing() async throws {
        await XCTAssertThrowsErrorAsync(
            try await HealthMetricService.recordScalar(kind: .oxygenSaturation, value: 130,
                                                       note: "", writer: writer, in: context)
        ) { XCTAssertEqual($0 as? HealthMetricService.ServiceError, .implausible) }
        XCTAssertEqual(try metrics().count, 0)
    }

    func testRecordVitalsWritesOnlyPresentFields() async throws {
        try await HealthMetricService.recordVitals(systolic: 120, diastolic: 80, pulse: 68,
                                                   spo2: nil, note: "", writer: writer, in: context)
        let all = try metrics()
        XCTAssertEqual(all.count, 2)             // BP row + pulse row, no SpO₂
        let bp = try XCTUnwrap(all.first { $0.metricKind == .bloodPressure })
        XCTAssertEqual(bp.value, 120)
        XCTAssertEqual(bp.secondaryValue, 80)
        XCTAssertTrue(all.contains { $0.metricKind == .pulse })
        XCTAssertFalse(all.contains { $0.metricKind == .oxygenSaturation })
    }

    func testVitalsBloodPressureBothOrNeither() async throws {
        await XCTAssertThrowsErrorAsync(
            try await HealthMetricService.recordVitals(systolic: 120, diastolic: nil, pulse: nil,
                                                       spo2: nil, note: "", writer: writer, in: context)
        ) { XCTAssertEqual($0 as? HealthMetricService.ServiceError, .bloodPressureIncomplete) }
        XCTAssertEqual(try metrics().count, 0)
    }

    func testDeleteRemovesRow() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 180, note: "",
                                                   writer: writer, in: context)
        let m = try XCTUnwrap(try metrics().first)
        HealthMetricService.delete(m, in: context)
        XCTAssertEqual(try metrics().count, 0)
    }

    func testCueContextLoadsPreviousWeightAndTodayWaterTotal() async throws {
        try await HealthMetricService.recordScalar(kind: .weight, value: 178, note: "",
                                                   writer: writer, in: context)
        let wctx = HealthMetricService.cueContext(for: .weight, in: context)
        XCTAssertEqual(wctx.previousValue, 178)
        XCTAssertNotNil(wctx.previousDate)

        try await HealthMetricService.recordScalar(kind: .water, value: 20, note: "",
                                                   writer: writer, in: context)
        try await HealthMetricService.recordScalar(kind: .water, value: 30, note: "",
                                                   writer: writer, in: context)
        let actx = HealthMetricService.cueContext(for: .water, in: context)
        XCTAssertEqual(actx.todayTotal, 50)
    }
}

/// Async throwing assertion helper (XCTest has no built-in async variant).
func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error but none thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
