import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DayQueryTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    private func fetchBatches() throws -> [Batch] {
        try context.fetch(FetchDescriptor<Batch>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.timeOfDay)]))
    }

    @Test
    func testDailyBatchRecursEveryDay() throws {
        let b = Batch(name: "Blue", recurrenceKind: .daily)
        context.insert(b)
        #expect(DayQuery.recurs(b, on: .now))
    }

    @Test
    func testWeekdaysBatchOnlyRecursOnListedWeekdays() throws {
        let day = Date.now
        let wd = Calendar.current.component(.weekday, from: day)
        let exclude = Batch(name: "Wk", recurrenceKind: .weekdays,
                            weekdays: [1,2,3,4,5,6,7].filter { $0 != wd })
        let include = Batch(name: "Wk2", recurrenceKind: .weekdays, weekdays: [wd])
        context.insert(exclude); context.insert(include)
        #expect(!DayQuery.recurs(exclude, on: day))
        #expect(DayQuery.recurs(include, on: day))
    }

    @Test
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
        #expect(days.count == 1)                       // Empty batch dropped
        #expect(days.first?.batch.name == "Blue")
        #expect(days.first?.meds.map { $0.item.medication?.name } == ["Active"])
        #expect(days.first?.state == .pending)         // nothing logged yet
    }

    @Test
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

        let item = try #require((blue.items ?? []).first { $0.medication?.name == "A" })
        let log = DoseLog(scheduledDate: .now, status: .taken, medication: item.medication, batchItem: item)
        context.insert(log)
        try context.save()

        let day = try #require(DayQuery.batchDays(from: try fetchBatches(), on: .now).first)
        #expect(day.state == .partial)
        let aDose = try #require(day.meds.first { $0.item.medication?.name == "A" })
        #expect(aDose.log != nil)
        let bDose = try #require(day.meds.first { $0.item.medication?.name == "B" })
        #expect(bDose.log == nil)
    }

    @Test
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
        #expect(prn.map { $0.med.name } == ["Tylenol"])
        #expect(prn.first?.logs.count == 1)
    }

    @Test
    func testCombineCombinesDateAndTime() throws {
        let cal = Calendar.current
        let dateComps = DateComponents(year: 2026, month: 6, day: 19)
        let date = cal.date(from: dateComps)!
        let timeComps = DateComponents(hour: 18, minute: 25, second: 30)
        let time = cal.date(from: timeComps)!

        let combined = DayQuery.combine(date: date, time: time)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: combined)
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 19)
        #expect(comps.hour == 18)
        #expect(comps.minute == 25)
        #expect(comps.second == 30)
    }
}

