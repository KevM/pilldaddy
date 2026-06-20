import HealthKit
import Testing
@testable import PillDaddy

struct HealthSampleMapperTests {
    @Test
    func testWeightMapsToPoundsQuantity() throws {
        let sample = try #require(
            HealthSampleMapper.map(HealthMetric(kind: .weight, value: 180, unit: "lb")).first
            as? HKQuantitySample)
        #expect(sample.quantityType == HKQuantityType(.bodyMass))
        #expect(abs(sample.quantity.doubleValue(for: .pound()) - 180) < 0.001)
    }

    @Test
    func testOxygenConvertsPercentToFraction() throws {
        let sample = try #require(
            HealthSampleMapper.map(HealthMetric(kind: .oxygenSaturation, value: 97, unit: "%")).first
            as? HKQuantitySample)
        #expect(abs(sample.quantity.doubleValue(for: .percent()) - 0.97) < 0.0001)
    }

    @Test
    func testBloodPressureMapsToCorrelationOfTwoSamples() throws {
        let corr = try #require(
            HealthSampleMapper.map(HealthMetric(kind: .bloodPressure, value: 120, secondaryValue: 80, unit: "mmHg")).first
            as? HKCorrelation)
        #expect(corr.correlationType == HKCorrelationType(.bloodPressure))
        #expect(corr.objects.count == 2)
        let sys = try #require(corr.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample)
        #expect(abs(sys.quantity.doubleValue(for: .millimeterOfMercury()) - 120) < 0.001)
        let dia = try #require(corr.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample)
        #expect(abs(dia.quantity.doubleValue(for: .millimeterOfMercury()) - 80) < 0.001)
    }
}
