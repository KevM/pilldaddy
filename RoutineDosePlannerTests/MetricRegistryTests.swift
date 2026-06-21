import XCTest
@testable import RoutineDosePlanner

final class MetricRegistryTests: XCTestCase {
    func testEveryKindHasACompleteDefinition() {
        for kind in MetricKind.allCases {
            let def = MetricRegistry.definition(for: kind)
            XCTAssertEqual(def.kind, kind)
            XCTAssertFalse(def.displayName.isEmpty)
            XCTAssertFalse(def.unit.isEmpty)
            XCTAssertFalse(def.healthAppBreadcrumb.isEmpty)
            XCTAssertLessThan(def.plausibleRange.lowerBound, def.plausibleRange.upperBound)
        }
    }

    func testOnlyWaterHasQuickAddAndCustomDefault() {
        XCTAssertEqual(MetricRegistry.definition(for: .water).quickAdd, [8, 12, 16])
        XCTAssertEqual(MetricRegistry.definition(for: .water).customAddDefault, 32)
        XCTAssertNil(MetricRegistry.definition(for: .weight).quickAdd)
        XCTAssertNil(MetricRegistry.definition(for: .weight).customAddDefault)
    }

    func testOnlyBloodPressureIsPaired() {
        XCTAssertEqual(MetricRegistry.definition(for: .bloodPressure).archetype, .paired)
        XCTAssertNotNil(MetricRegistry.definition(for: .bloodPressure).secondaryPlausibleRange)
        XCTAssertEqual(MetricRegistry.definition(for: .weight).archetype, .scalar)
    }
}
