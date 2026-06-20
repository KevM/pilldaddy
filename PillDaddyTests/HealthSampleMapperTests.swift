import HealthKit
import XCTest
@testable import PillDaddy

final class HealthSampleMapperTests: XCTestCase {
    func testWeightMapsToPoundsQuantity() throws {
        let sample = try XCTUnwrap(
            HealthSampleMapper.map(HealthMetric(kind: .weight, value: 180, unit: "lb")).first
            as? HKQuantitySample)
        XCTAssertEqual(sample.quantityType, HKQuantityType(.bodyMass))
        XCTAssertEqual(sample.quantity.doubleValue(for: .pound()), 180, accuracy: 0.001)
    }

    func testOxygenConvertsPercentToFraction() throws {
        let sample = try XCTUnwrap(
            HealthSampleMapper.map(HealthMetric(kind: .oxygenSaturation, value: 97, unit: "%")).first
            as? HKQuantitySample)
        XCTAssertEqual(sample.quantity.doubleValue(for: .percent()), 0.97, accuracy: 0.0001)
    }

    func testBloodPressureMapsToCorrelationOfTwoSamples() throws {
        let corr = try XCTUnwrap(
            HealthSampleMapper.map(HealthMetric(kind: .bloodPressure, value: 120, secondaryValue: 80, unit: "mmHg")).first
            as? HKCorrelation)
        XCTAssertEqual(corr.correlationType, HKCorrelationType(.bloodPressure))
        XCTAssertEqual(corr.objects.count, 2)
        let sys = try XCTUnwrap(corr.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample)
        XCTAssertEqual(sys.quantity.doubleValue(for: .millimeterOfMercury()), 120, accuracy: 0.001)
        let dia = try XCTUnwrap(corr.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample)
        XCTAssertEqual(dia.quantity.doubleValue(for: .millimeterOfMercury()), 80, accuracy: 0.001)
    }
}
