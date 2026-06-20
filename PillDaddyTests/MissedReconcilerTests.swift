import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MissedReconcilerTests: XCTestCase {

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

    @discardableResult
    private func makeBatch(hour: Int, recurrence: RecurrenceKind = .daily,
                           weekdays: [Int]? = nil) -> (Batch, BatchItem) {
        let t = cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        let batch = Batch(name: "B\(hour)", timeOfDay: t,
                          recurrenceKind: recurrence, weekdays: weekdays)
        batch.uuid = UUID()
        context.insert(batch)
        let med = Medication(name: "Med\(hour)")
        context.insert(med)
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(item)
        try? context.save()
        return (batch, item)
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    func testWritesMissedForUnloggedSlotPastGrace() throws {
        let (batch, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        let all = try logs()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, DoseStatus.missed.rawValue)
        XCTAssertNil(all.first?.takenAt)
        XCTAssertEqual(all.first?.snapshotMedName, "Med9")
    }

    func testDoesNotWriteBeforeGrace() throws {
        let (batch, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(60 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testPreservesExistingTakenOrSkipped() throws {
        let (batch, item) = makeBatch(hour: 9)
        DoseLogService.logBatchTaken(batch, on: .now, items: [item], takenAt: .now, note: "", in: context)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        let all = try logs()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, DoseStatus.taken.rawValue)
    }

    func testIdempotent() throws {
        let (batch, _) = makeBatch(hour: 9)
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        XCTAssertEqual(try logs().count, 1)
    }

    func testExcludesDiscontinuedMed() throws {
        let (batch, item) = makeBatch(hour: 9)
        item.medication?.isActive = false
        try context.save()
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        XCTAssertEqual(try logs().count, 0)
    }

    func testRespectsWeekdayRecurrence() throws {
        let today = cal.component(.weekday, from: .now)
        let other = (today % 7) + 1
        let (batch, _) = makeBatch(hour: 9, recurrence: .weekdays, weekdays: [other])
        let now = DayQuery.slotDate(for: batch, on: .now).addingTimeInterval(121 * 60)
        MissedReconciler.reconcile(batches: [batch], now: now, graceMinutes: 120, lookbackDays: 0, in: context)
        XCTAssertEqual(try logs().count, 0)
    }
}
