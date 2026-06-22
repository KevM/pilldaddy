import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct DayQueryTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    private func fetchRoutines() throws -> [Routine] {
        try context.fetch(FetchDescriptor<Routine>(
            sortBy: [SortDescriptor(\.timeOfDay), SortDescriptor(\.uuid)]))
    }

    @Test
    func testDailyRoutineRecursEveryDay() throws {
        let b = Routine(name: "Blue", recurrenceKind: .daily)
        context.insert(b)
        #expect(DayQuery.recurs(b, on: .now))
    }

    @Test
    func testWeekdaysRoutineOnlyRecursOnListedWeekdays() throws {
        let day = Date.now
        let wd = Calendar.current.component(.weekday, from: day)
        let exclude = Routine(name: "Wk", recurrenceKind: .weekdays,
                            weekdays: [1,2,3,4,5,6,7].filter { $0 != wd })
        let include = Routine(name: "Wk2", recurrenceKind: .weekdays, weekdays: [wd])
        context.insert(exclude); context.insert(include)
        #expect(!DayQuery.recurs(exclude, on: day))
        #expect(DayQuery.recurs(include, on: day))
    }

    @Test
    func testRoutineDaysExcludeDiscontinuedAndPRNAndEmptyRoutines() throws {
        let blue = Routine(name: "Blue")
        let empty = Routine(name: "Empty")
        context.insert(blue); context.insert(empty)

        let active = try MedicationService.addMedication(
            name: "Active", strengthValue: 10, strengthUnit: "mg", form: "tablet", isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        _ = active
        let stopped = try MedicationService.addMedication(
            name: "Stopped", strengthValue: 10, strengthUnit: "mg", form: "tablet", isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        try MedicationService.discontinue(stopped, reason: "x", in: context)

        let days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        #expect(days.count == 1)                       // Empty routine dropped
        #expect(days.first?.routine.name == "Blue")
        #expect(days.first?.meds.map { $0.item.medication?.name } == ["Active"])
        #expect(days.first?.state == .pending)         // nothing logged yet
    }

    @Test
    func testRoutineDayStateReflectsExistingLogs() throws {
        let blue = Routine(name: "Blue", timeOfDay: .now)
        context.insert(blue)
        let med = try MedicationService.addMedication(
            name: "A", strengthValue: 1, strengthUnit: "mg", form: "tablet", isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        let med2 = try MedicationService.addMedication(
            name: "B", strengthValue: 1, strengthUnit: "mg", form: "tablet", isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        _ = (med, med2)

        let item = try #require((blue.items ?? []).first { $0.medication?.name == "A" })
        let log = DoseLog(scheduledDate: .now, status: .taken, medication: item.medication, routineItem: item)
        context.insert(log)
        try context.save()

        let day = try #require(DayQuery.routineDays(from: try fetchRoutines(), on: .now).first)
        #expect(day.state == .partial)
        let aDose = try #require(day.meds.first { $0.item.medication?.name == "A" })
        #expect(aDose.log != nil)
        let bDose = try #require(day.meds.first { $0.item.medication?.name == "B" })
        #expect(bDose.log == nil)
    }

    @Test
    func testPRNDosesReturnActivePRNWithThatDaysLogs() throws {
        let tylenol = try MedicationService.addMedication(
            name: "Tylenol", strengthValue: 500, strengthUnit: "mg", form: "tablet", isPRN: true, notes: "",
            placements: [], reason: "", in: context)
        context.insert(DoseLog(scheduledDate: .now, takenAt: .now, status: .taken,
                               quantity: 1.0, isPRN: true, medication: tylenol, routineItem: nil))
        // a log from a different day must not appear
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        context.insert(DoseLog(scheduledDate: yesterday, takenAt: yesterday, status: .taken,
                               quantity: 1.0, isPRN: true, medication: tylenol, routineItem: nil))
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

    @Test
    func testPrnDosesUsesIsPRNFlagNotRoutineItemLink() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        // A scheduled (non-PRN) log whose routineItem link has been nullified must NOT
        // be classified as PRN.
        let scheduled = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg",
                                   form: "tablet", isPRN: false)
        context.insert(scheduled)
        let orphanLog = DoseLog(scheduledDate: .now, status: .taken,
                                medication: scheduled, routineItem: nil)
        orphanLog.isPRN = false
        context.insert(orphanLog)

        // A genuine PRN log.
        let tylenol = Medication(name: "Tylenol", strengthValue: 500, strengthUnit: "mg",
                                 form: "tablet", isPRN: true)
        context.insert(tylenol)
        let prnLog = DoseLog(scheduledDate: .now, status: .taken,
                             medication: tylenol, routineItem: nil)
        prnLog.isPRN = true
        context.insert(prnLog)
        try context.save()

        let prnMeds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isActive && $0.isPRN }))
        let result = DayQuery.prnDoses(from: prnMeds, on: .now)
        let totalLogs = result.reduce(0) { $0 + $1.logs.count }
        #expect(totalLogs == 1)                       // only the genuine PRN log
    }

    @Test
    func testRoutineDayStateAndIsCompletedAllStatuses() throws {
        let blue = Routine(name: "Blue", timeOfDay: .now)
        context.insert(blue)
        _ = try MedicationService.addMedication(
            name: "A", strengthValue: 1, strengthUnit: "mg", form: "tablet", isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        _ = try MedicationService.addMedication(
            name: "B", strengthValue: 1, strengthUnit: "mg", form: "tablet", isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        let itemA = try #require((blue.items ?? []).first { $0.medication?.name == "A" })
        let itemB = try #require((blue.items ?? []).first { $0.medication?.name == "B" })

        // 1. Pending (no logs)
        var days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        var day = try #require(days.first)
        #expect(day.state == .pending)
        #expect(!day.isCompleted)

        // 2. Partial (only A logged)
        let logA = DoseLog(scheduledDate: .now, status: .taken, medication: itemA.medication, routineItem: itemA)
        context.insert(logA)
        try context.save()
        days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        day = try #require(days.first)
        #expect(day.state == .partial)
        #expect(!day.isCompleted)

        // 3. Taken (both taken)
        let logB = DoseLog(scheduledDate: .now, status: .taken, medication: itemB.medication, routineItem: itemB)
        context.insert(logB)
        try context.save()
        days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        day = try #require(days.first)
        #expect(day.state == .taken)
        #expect(day.isCompleted)

        // 4. Skipped (both skipped)
        logA.status = DoseStatus.skipped.rawValue
        logB.status = DoseStatus.skipped.rawValue
        try context.save()
        days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        day = try #require(days.first)
        #expect(day.state == .skipped)
        #expect(day.isCompleted)

        // 5. Missed (both missed)
        logA.status = DoseStatus.missed.rawValue
        logB.status = DoseStatus.missed.rawValue
        try context.save()
        days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        day = try #require(days.first)
        #expect(day.state == .missed)
        #expect(day.isCompleted)

        // 6. Completed/Mixed (A taken, B skipped)
        logA.status = DoseStatus.taken.rawValue
        logB.status = DoseStatus.skipped.rawValue
        try context.save()
        days = DayQuery.routineDays(from: try fetchRoutines(), on: .now)
        day = try #require(days.first)
        #expect(day.state == .completed)
        #expect(day.isCompleted)
    }
}

