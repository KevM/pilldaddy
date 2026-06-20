import XCTest
@testable import PillDaddy

final class ReminderTierTests: XCTestCase {

    func testTierThresholds() {
        let grace: TimeInterval = 120 * 60
        // calm: < 1/3 of grace (< 40 min)
        XCTAssertEqual(ReminderTier.forElapsed(0, grace: grace), .calm)
        XCTAssertEqual(ReminderTier.forElapsed(39 * 60, grace: grace), .calm)
        // overdue: 1/3 .. 3/4 (40 .. 90 min)
        XCTAssertEqual(ReminderTier.forElapsed(45 * 60, grace: grace), .overdue)
        XCTAssertEqual(ReminderTier.forElapsed(89 * 60, grace: grace), .overdue)
        // urgent: >= 3/4 (>= 90 min)
        XCTAssertEqual(ReminderTier.forElapsed(107 * 60, grace: grace), .urgent)
        XCTAssertEqual(ReminderTier.forElapsed(130 * 60, grace: grace), .urgent)
    }

    func testNegativeElapsedIsCalm() {
        XCTAssertEqual(ReminderTier.forElapsed(-60, grace: 7200), .calm)
    }

    func testZeroGraceIsUrgent() {
        XCTAssertEqual(ReminderTier.forElapsed(0, grace: 0), .urgent)
    }
}
