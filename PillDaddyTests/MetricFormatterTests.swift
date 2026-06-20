import Testing
@testable import PillDaddy

struct MetricFormatterTests {
    @Test
    func testWholeNumbersDropDecimal() {
        #expect(MetricFormatter.string(176, unit: "lb") == "176 lb")
    }

    @Test
    func testFractionsKeepOneDecimal() {
        #expect(MetricFormatter.string(97.5, unit: "%") == "97.5 %")
    }

    @Test
    func testBloodPressurePair() {
        #expect(MetricFormatter.bloodPressure(120, 80) == "120/80")
    }
}

