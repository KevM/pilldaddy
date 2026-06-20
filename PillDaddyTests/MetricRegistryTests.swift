import Testing
@testable import PillDaddy

struct MetricRegistryTests {
    @Test
    func testEveryKindHasACompleteDefinition() {
        for kind in MetricKind.allCases {
            let def = MetricRegistry.definition(for: kind)
            #expect(def.kind == kind)
            #expect(!def.displayName.isEmpty)
            #expect(!def.unit.isEmpty)
            #expect(!def.healthAppBreadcrumb.isEmpty)
            #expect(def.plausibleRange.lowerBound < def.plausibleRange.upperBound)
        }
    }

    @Test
    func testOnlyWaterHasQuickAddAndCustomDefault() {
        #expect(MetricRegistry.definition(for: .water).quickAdd == [8, 12, 16])
        #expect(MetricRegistry.definition(for: .water).customAddDefault == 32)
        #expect(MetricRegistry.definition(for: .weight).quickAdd == nil)
        #expect(MetricRegistry.definition(for: .weight).customAddDefault == nil)
    }

    @Test
    func testOnlyBloodPressureIsPaired() {
        #expect(MetricRegistry.definition(for: .bloodPressure).archetype == .paired)
        #expect(MetricRegistry.definition(for: .bloodPressure).secondaryPlausibleRange != nil)
        #expect(MetricRegistry.definition(for: .weight).archetype == .scalar)
    }
}

