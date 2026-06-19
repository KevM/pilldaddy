import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DayQueryTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    private func fetchBatches() throws -> [Batch] {
        try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]))
    }

    func testDailyBatchRecursEveryDay() throws {
        let b = Batch(name: "Blue", recurrenceKind: .daily)
        context.insert(b)
        XCTAssertTrue(DayQuery.recurs(b, on: .now))
    }

    func testWeekdaysBatchOnlyRecursOnListedWeekdays() throws {
        let day = Date.now
        let wd = Calendar.current.component(.weekday, from: day)
        let exclude = Batch(name: "Wk", recurrenceKind: .weekdays,
                            weekdays: [1,2,3,4,5,6,7].filter { $0 != wd })
        let include = Batch(name: "Wk2", recurrenceKind: .weekdays, weekdays: [wd])
        context.insert(exclude); context.insert(include)
        XCTAssertFalse(DayQuery.recurs(exclude, on: day))
        XCTAssertTrue(DayQuery.recurs(include, on: day))
    }

    func testBatchDaysExcludeDiscontinuedAndPRNAndEmptyBatches() throws {
        let blue = Batch(name: "Blue", sortOrder: 0)
        let empty = Batch(name: "Empty", sortOrder: 1)
        context.insert(blue); context.insert(empty)

        let active = MedicationService.addMedication(
            name: "Active", strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = active
        let stopped = MedicationService.addMedication(
            name: "Stopped", strength: "10mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        try MedicationService.discontinue(stopped, reason: "x", in: context)

        let days = DayQuery.batchDays(from: try fetchBatches(), on: .now)
        XCTAssertEqual(days.count, 1)                       // Empty batch dropped
        XCTAssertEqual(days.first?.batch.name, "Blue")
        XCTAssertEqual(days.first?.meds.map { $0.item.medication?.name }, ["Active"])
        XCTAssertEqual(days.first?.state, .pending)         // nothing logged yet
    }

    func testBatchDayStateReflectsExistingLogs() throws {
        let blue = Batch(name: "Blue", timeOfDay: .now, sortOrder: 0)
        context.insert(blue)
        let med = MedicationService.addMedication(
            name: "A", strength: "1mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        let med2 = MedicationService.addMedication(
            name: "B", strength: "1mg", form: "tablet", isPRN: false, notes: "",
            placements: [(batch: blue, quantity: 1.0)], reason: "", in: context)
        _ = (med, med2)

        let item = try XCTUnwrap((blue.items ?? []).first { $0.medication?.name == "A" })
        let log = DoseLog(scheduledDate: .now, status: .taken, medication: item.medication, batchItem: item)
        context.insert(log)
        try context.save()

        let day = try XCTUnwrap(DayQuery.batchDays(from: try fetchBatches(), on: .now).first)
        XCTAssertEqual(day.state, .partial)
        let aDose = try XCTUnwrap(day.meds.first { $0.item.medication?.name == "A" })
        XCTAssertNotNil(aDose.log)
        let bDose = try XCTUnwrap(day.meds.first { $0.item.medication?.name == "B" })
        XCTAssertNil(bDose.log)
    }

    func testPRNDosesReturnActivePRNWithThatDaysLogs() throws {
        let tylenol = MedicationService.addMedication(
            name: "Tylenol", strength: "500mg", form: "tablet", isPRN: true, notes: "",
            placements: [], reason: "", in: context)
        context.insert(DoseLog(scheduledDate: .now, takenAt: .now, status: .taken,
                               quantity: 1.0, medication: tylenol, batchItem: nil))
        // a log from a different day must not appear
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        context.insert(DoseLog(scheduledDate: yesterday, takenAt: yesterday, status: .taken,
                               quantity: 1.0, medication: tylenol, batchItem: nil))
        try context.save()

        let meds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive && $0.isPRN }, sortBy: [SortDescriptor(\.name)]))
        let prn = DayQuery.prnDoses(from: meds, on: .now)
        XCTAssertEqual(prn.map { $0.med.name }, ["Tylenol"])
        XCTAssertEqual(prn.first?.logs.count, 1)
    }
}
