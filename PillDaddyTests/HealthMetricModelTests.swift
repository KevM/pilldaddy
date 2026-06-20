import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct HealthMetricModelTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test
    func testInsertAndFetchHealthMetric() throws {
        let m = HealthMetric(kind: .bloodPressure, value: 120, secondaryValue: 80,
                             unit: "mmHg", recordedAt: .now)
        context.insert(m)
        try context.save()

        let all = try context.fetch(FetchDescriptor<HealthMetric>())
        #expect(all.count == 1)
        let fetched = try #require(all.first)
        #expect(fetched.metricKind == .bloodPressure)
        #expect(fetched.value == 120)
        #expect(fetched.secondaryValue == 80)
        #expect(!fetched.healthKitSynced)
        #expect(fetched.healthKitSampleUUID == nil)
    }

    @Test
    func testMetricKindFallsBackForUnknownRawString() throws {
        let m = HealthMetric(kind: .weight, value: 1, secondaryValue: nil, unit: "lb", recordedAt: .now)
        m.kind = "garbage"
        #expect(m.metricKind == .weight)
    }
}

