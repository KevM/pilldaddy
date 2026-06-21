import XCTest
@testable import RoutineDosePlanner

final class MetricCueTests: XCTestCase {
    private func cue(_ kind: MetricKind, _ v: Double, _ s: Double? = nil,
                     _ ctx: CueContext = .empty) -> MetricCue {
        MetricRegistry.definition(for: kind).cue(v, s, ctx)
    }

    func testBloodPressureWorseOfTwoAxes() {
        XCTAssertEqual(cue(.bloodPressure, 110, 75), .normal)
        XCTAssertEqual(cue(.bloodPressure, 120, 78), .caution)   // systolic high
        XCTAssertEqual(cue(.bloodPressure, 110, 95), .caution)   // diastolic high
        XCTAssertEqual(cue(.bloodPressure, 185, 78), .alert)     // systolic crisis
        XCTAssertEqual(cue(.bloodPressure, 150, 125), .alert)    // diastolic crisis
        XCTAssertEqual(cue(.bloodPressure, 88, 58), .caution)    // both low
        XCTAssertEqual(cue(.bloodPressure, 120, 38), .alert)     // diastolic severe-low
    }

    func testPulse() {
        XCTAssertEqual(cue(.pulse, 60), .normal)
        XCTAssertEqual(cue(.pulse, 100), .normal)
        XCTAssertEqual(cue(.pulse, 50), .caution)
        XCTAssertEqual(cue(.pulse, 101), .caution)
        XCTAssertEqual(cue(.pulse, 49), .alert)
        XCTAssertEqual(cue(.pulse, 121), .alert)
    }

    func testOxygen() {
        XCTAssertEqual(cue(.oxygenSaturation, 95), .normal)
        XCTAssertEqual(cue(.oxygenSaturation, 94), .caution)
        XCTAssertEqual(cue(.oxygenSaturation, 90), .alert)
    }

    func testWaterPerEntry() {
        XCTAssertEqual(cue(.water, 32), .normal)
        XCTAssertEqual(cue(.water, 33), .caution)
        XCTAssertEqual(cue(.water, 65), .alert)
    }

    func testWaterDailyTotalWorseOf() {
        func ctx(_ total: Double) -> CueContext {
            CueContext(previousValue: nil, previousDate: nil, todayTotal: total, now: .now)
        }
        XCTAssertEqual(cue(.water, 16, nil, ctx(84)), .normal)   // total 100
        XCTAssertEqual(cue(.water, 16, nil, ctx(90)), .caution)  // total 106
        XCTAssertEqual(cue(.water, 16, nil, ctx(130)), .alert)   // total 146
        XCTAssertEqual(cue(.water, 70, nil, ctx(0)), .alert)     // per-entry alert wins
    }

    func testWeightDelta() {
        func ctx(prev: Double, daysAgo: Double) -> CueContext {
            CueContext(previousValue: prev,
                       previousDate: Date.now.addingTimeInterval(-daysAgo * 86_400),
                       todayTotal: nil, now: .now)
        }
        XCTAssertEqual(cue(.weight, 178, nil, .empty), .normal)              // no prior
        XCTAssertEqual(cue(.weight, 180, nil, ctx(prev: 178, daysAgo: 3)), .normal) // +2/3d
        XCTAssertEqual(cue(.weight, 181, nil, ctx(prev: 178, daysAgo: 5)), .caution) // +3/5d
        XCTAssertEqual(cue(.weight, 173, nil, ctx(prev: 178, daysAgo: 4)), .alert)   // -5/4d
        XCTAssertEqual(cue(.weight, 180, nil, ctx(prev: 178, daysAgo: 0.99)), .alert)   // +2/1d
    }
}
