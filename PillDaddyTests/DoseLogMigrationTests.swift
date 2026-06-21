import Foundation
import SwiftData
import Testing
@testable import PillDaddy

// Serialized: these tests mutate the process-global `didRunDoseLogPRNBackfill`
// UserDefaults key, so they must not run in parallel with each other.
@Suite(.serialized)
@MainActor
struct DoseLogMigrationTests {

    @Test
    func testBackfillTagsLegacyNilBatchItemLogsAsPRN() throws {
        let userDefaultsKey = "didRunDoseLogPRNBackfill"
        UserDefaults.standard.set(false, forKey: userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: userDefaultsKey) }

        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Tylenol", strengthValue: 500, strengthUnit: "mg", isPRN: true)
        context.insert(med)

        // Legacy PRN log: nil routineItem, isPRN still at the migration default of false.
        let legacy = DoseLog(scheduledDate: .now, status: .taken, medication: med, routineItem: nil)
        legacy.isPRN = false
        context.insert(legacy)

        // Scheduled log with a live routineItem must stay non-PRN.
        let batch = Routine(name: "Morning")
        context.insert(batch)
        let item = RoutineItem(quantity: 1.0, medication: med, routine: batch)
        context.insert(item)
        let scheduled = DoseLog(scheduledDate: .now, status: .taken, medication: med, routineItem: item)
        scheduled.isPRN = false
        context.insert(scheduled)
        try context.save()

        DoseLogMigration.backfillPRNFlag(in: context)

        #expect(legacy.isPRN == true)
        #expect(scheduled.isPRN == false)
    }

    @Test
    func testBackfillSkippedIfAlreadyRunOrAfterBatchDeletion() throws {
        let userDefaultsKey = "didRunDoseLogPRNBackfill"
        UserDefaults.standard.set(false, forKey: userDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: userDefaultsKey) }

        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", isPRN: false)
        context.insert(med)
        let batch = Routine(name: "Morning")
        context.insert(batch)
        let item = RoutineItem(quantity: 1.0, medication: med, routine: batch)
        context.insert(item)

        // Scheduled log
        let log = DoseLog(scheduledDate: .now, status: .taken, medication: med, routineItem: item)
        log.isPRN = false
        context.insert(log)
        try context.save()

        // 1. Run backfill. Since 'log' has a routineItem, it must NOT be backfilled.
        DoseLogMigration.backfillPRNFlag(in: context)
        #expect(log.isPRN == false)
        #expect(UserDefaults.standard.bool(forKey: userDefaultsKey) == true)

        // 2. Now discontinue/make medication inactive so we can delete the batch, nullifying the routineItem link on the log.
        med.isActive = false
        try MedicationService.deleteBatch(batch, in: context)
        #expect(log.routineItem == nil)
        #expect(log.isPRN == false)

        // 3. Run backfill again. Since it already ran, it should return early and not tag the orphan log.
        DoseLogMigration.backfillPRNFlag(in: context)
        #expect(log.isPRN == false)
    }
}
