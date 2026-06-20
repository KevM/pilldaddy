import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogMigrationTests {

    @Test
    func testBackfillTagsLegacyNilBatchItemLogsAsPRN() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        let med = Medication(name: "Tylenol", strengthValue: 500, strengthUnit: "mg", isPRN: true)
        context.insert(med)

        // Legacy PRN log: nil batchItem, isPRN still at the migration default of false.
        let legacy = DoseLog(scheduledDate: .now, status: .taken, medication: med, batchItem: nil)
        legacy.isPRN = false
        context.insert(legacy)

        // Scheduled log with a live batchItem must stay non-PRN.
        let batch = Batch(name: "Morning")
        context.insert(batch)
        let item = BatchItem(quantity: 1.0, medication: med, batch: batch)
        context.insert(item)
        let scheduled = DoseLog(scheduledDate: .now, status: .taken, medication: med, batchItem: item)
        scheduled.isPRN = false
        context.insert(scheduled)
        try context.save()

        DoseLogMigration.backfillPRNFlag(in: context)

        #expect(legacy.isPRN == true)
        #expect(scheduled.isPRN == false)
    }
}
