import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class HealthMetricModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil; container = nil
        try await super.tearDown()
    }

    func testInsertAndFetchHealthMetric() throws {
        let m = HealthMetric(kind: .bloodPressure, value: 120, secondaryValue: 80,
                             unit: "mmHg", recordedAt: .now)
        context.insert(m)
        try context.save()

        let all = try context.fetch(FetchDescriptor<HealthMetric>())
        XCTAssertEqual(all.count, 1)
        let fetched = try XCTUnwrap(all.first)
        XCTAssertEqual(fetched.metricKind, .bloodPressure)
        XCTAssertEqual(fetched.value, 120)
        XCTAssertEqual(fetched.secondaryValue, 80)
        XCTAssertFalse(fetched.healthKitSynced)
        XCTAssertNil(fetched.healthKitSampleUUID)
    }

    func testMetricKindFallsBackForUnknownRawString() throws {
        let m = HealthMetric(kind: .weight, value: 1, secondaryValue: nil, unit: "lb", recordedAt: .now)
        m.kind = "garbage"
        XCTAssertEqual(m.metricKind, .weight)
    }
}
