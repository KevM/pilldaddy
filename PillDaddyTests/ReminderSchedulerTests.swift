import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class ReminderSchedulerTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var cal: Calendar { Calendar.current }

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil; container = nil
        try await super.tearDown()
    }

    /// A daily batch at the given clock time with one active scheduled med.
    private func makeBatch(hour: Int, minute: Int = 0,
                           recurrence: RecurrenceKind = .daily, weekdays: [Int]? = nil) -> Batch {
        let t = cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        let batch = Batch(name: "B\(hour)", timeOfDay: t,
                          recurrenceKind: recurrence, weekdays: weekdays)
        context.insert(batch)

        let med = Medication(name: "Med\(hour)")
        context.insert(med)
        context.insert(BatchItem(quantity: 1.0, medication: med, batch: batch))
        try? context.save()
        return batch
    }

    /// `now` set to 1 hour before the batch slot today, so all reminders are in the future.
    private func nowBefore(_ batch: Batch) -> Date {
        DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(-3600)
    }

    func testDailyBatchEmitsHeadsUpDueAndThreeFollowUps() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        let kinds = plan.map(\.kind).sorted { $0.rawValue < $1.rawValue }
        XCTAssertEqual(plan.count, 5)   // headsUp + due + 3 follow-ups (30/60/90)
        XCTAssertEqual(kinds.filter { $0 == .headsUp }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .due }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .followUp }.count, 3)
    }

    func testHeadsUpDisabledDropsHeadsUp() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: false, masterEnabled: true)
        XCTAssertFalse(plan.contains { $0.kind == .headsUp })
        XCTAssertEqual(plan.count, 4)
    }

    func testFollowUpsClippedToGraceWindow() {
        let batch = makeBatch(hour: 9)
        // 60-minute grace → only the +30 follow-up is strictly before the cutoff.
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 60, headsUpEnabled: true, masterEnabled: true)
        XCTAssertEqual(plan.filter { $0.kind == .followUp }.count, 1)
    }

    func testMasterDisabledEmitsNothing() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testPastFireDatesAreOmitted() {
        let batch = makeBatch(hour: 9)
        // now = slot + 40 min → headsUp, due, +30 are in the past; only +60, +90 remain.
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(40 * 60)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: now, horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })
        XCTAssertEqual(plan.filter { $0.kind == .followUp }.count, 2)
    }

    func testWeekdayBatchAbsentOnExcludedDay() {
        let today = cal.component(.weekday, from: .now)
        let other = (today % 7) + 1   // a different weekday
        let batch = makeBatch(hour: 9, recurrence: .weekdays, weekdays: [other])
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        XCTAssertTrue(plan.isEmpty)
    }

    func testCompletedSlotIsSkipped() {
        let batch = makeBatch(hour: 9)
        let slot = DayQuery.slotDate(for: batch, on: .now)
        let key = ReminderScheduler.slotKey(batchUUID: batch.uuid.uuidString, slot: slot)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true,
            completedSlots: [key])
        XCTAssertTrue(plan.isEmpty)
    }

    func testRespectsLimit() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true, limit: 2)
        XCTAssertEqual(plan.count, 2)
        // earliest fire dates kept
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted { $0 < $1 })
    }

    func testIdentifiersAreUnique() {
        let batch = makeBatch(hour: 9)
        let plan = ReminderScheduler.plan(
            batches: [batch], now: nowBefore(batch), horizonDays: 1,
            graceMinutes: 120, headsUpEnabled: true, masterEnabled: true)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
    }
}
