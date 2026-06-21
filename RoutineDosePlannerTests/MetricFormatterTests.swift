import XCTest
@testable import RoutineDosePlanner

final class MetricFormatterTests: XCTestCase {
    func testWholeNumbersDropDecimal() {
        XCTAssertEqual(MetricFormatter.string(176, unit: "lb"), "176 lb")
    }
    func testFractionsKeepOneDecimal() {
        XCTAssertEqual(MetricFormatter.string(97.5, unit: "%"), "97.5 %")
    }
    func testBloodPressurePair() {
        XCTAssertEqual(MetricFormatter.bloodPressure(120, 80), "120/80")
    }
}
