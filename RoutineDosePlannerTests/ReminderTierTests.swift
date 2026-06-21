import Foundation
import Testing
@testable import RoutineDosePlanner

struct ReminderTierTests {

    @Test
    func testTierThresholds() {
        let grace: TimeInterval = 120 * 60
        // calm: < 1/3 of grace (< 40 min)
        #expect(ReminderTier.forElapsed(0, grace: grace) == .calm)
        #expect(ReminderTier.forElapsed(39 * 60, grace: grace) == .calm)
        // overdue: 1/3 .. 3/4 (40 .. 90 min)
        #expect(ReminderTier.forElapsed(45 * 60, grace: grace) == .overdue)
        #expect(ReminderTier.forElapsed(89 * 60, grace: grace) == .overdue)
        // urgent: >= 3/4 (>= 90 min)
        #expect(ReminderTier.forElapsed(107 * 60, grace: grace) == .urgent)
        #expect(ReminderTier.forElapsed(130 * 60, grace: grace) == .urgent)
     }

    @Test
    func testNegativeElapsedIsCalm() {
        #expect(ReminderTier.forElapsed(-60, grace: 7200) == .calm)
    }

    @Test
    func testZeroGraceIsUrgent() {
        #expect(ReminderTier.forElapsed(0, grace: 0) == .urgent)
    }
}

