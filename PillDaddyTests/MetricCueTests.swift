import Foundation
import Testing
@testable import PillDaddy

struct MetricCueTests {
    private func cue(_ kind: MetricKind, _ v: Double, _ s: Double? = nil,
                     _ ctx: CueContext = .empty) -> MetricCue {
        MetricRegistry.definition(for: kind).cue(v, s, ctx)
    }

    @Test
    func testBloodPressureWorseOfTwoAxes() {
        #expect(cue(.bloodPressure, 110, 75) == .normal)
        #expect(cue(.bloodPressure, 120, 78) == .caution)   // systolic high
        #expect(cue(.bloodPressure, 110, 95) == .caution)   // diastolic high
        #expect(cue(.bloodPressure, 185, 78) == .alert)     // systolic crisis
        #expect(cue(.bloodPressure, 150, 125) == .alert)    // diastolic crisis
        #expect(cue(.bloodPressure, 88, 58) == .caution)    // both low
        #expect(cue(.bloodPressure, 120, 38) == .alert)     // diastolic severe-low
    }

    @Test
    func testPulse() {
        #expect(cue(.pulse, 60) == .normal)
        #expect(cue(.pulse, 100) == .normal)
        #expect(cue(.pulse, 50) == .caution)
        #expect(cue(.pulse, 101) == .caution)
        #expect(cue(.pulse, 49) == .alert)
        #expect(cue(.pulse, 121) == .alert)
    }

    @Test
    func testOxygen() {
        #expect(cue(.oxygenSaturation, 95) == .normal)
        #expect(cue(.oxygenSaturation, 94) == .caution)
        #expect(cue(.oxygenSaturation, 90) == .alert)
    }

    @Test
    func testWaterPerEntry() {
        #expect(cue(.water, 32) == .normal)
        #expect(cue(.water, 33) == .caution)
        #expect(cue(.water, 65) == .alert)
    }

    @Test
    func testWaterDailyTotalWorseOf() {
        func ctx(_ total: Double) -> CueContext {
            CueContext(previousValue: nil, previousDate: nil, todayTotal: total, now: .now)
        }
        #expect(cue(.water, 16, nil, ctx(84)) == .normal)   // total 100
        #expect(cue(.water, 16, nil, ctx(90)) == .caution)  // total 106
        #expect(cue(.water, 16, nil, ctx(130)) == .alert)   // total 146
        #expect(cue(.water, 70, nil, ctx(0)) == .alert)     // per-entry alert wins
    }

    @Test
    func testWeightDelta() {
        func ctx(prev: Double, daysAgo: Double) -> CueContext {
            CueContext(previousValue: prev,
                       previousDate: Date.now.addingTimeInterval(-daysAgo * 86_400),
                       todayTotal: nil, now: .now)
        }
        #expect(cue(.weight, 178, nil, .empty) == .normal)              // no prior
        #expect(cue(.weight, 180, nil, ctx(prev: 178, daysAgo: 3)) == .normal) // +2/3d
        #expect(cue(.weight, 181, nil, ctx(prev: 178, daysAgo: 5)) == .caution) // +3/5d
        #expect(cue(.weight, 173, nil, ctx(prev: 178, daysAgo: 4)) == .alert)   // -5/4d
        #expect(cue(.weight, 180, nil, ctx(prev: 178, daysAgo: 0.99)) == .alert)   // +2/1d
    }
}

