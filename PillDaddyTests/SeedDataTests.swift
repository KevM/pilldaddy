import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class SeedDataTests: XCTestCase {
    func testSeedPopulatesWorkedExampleRegime() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()

        // Metoprolol exists in two batches at 1.0 and 0.5
        let metoprolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Metoprolol" })).first)
        XCTAssertEqual(metoprolol.batchItems?.count, 2)
        XCTAssertEqual((metoprolol.batchItems ?? []).map(\.quantity).sorted(), [0.5, 1.0])

        // At least one PRN med
        let prnMeds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isPRN == true }))
        XCTAssertGreaterThanOrEqual(prnMeds.count, 1)

        // At least one change-event in the history
        let events = try context.fetch(FetchDescriptor<MedicationChangeEvent>())
        XCTAssertGreaterThanOrEqual(events.count, 1)
    }

    func testSeedIsIdempotent() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()
        let countAfterFirst = try context.fetch(FetchDescriptor<Medication>()).count

        SeedData.seedIfEmpty(context)   // second call must be a no-op
        try context.save()
        let countAfterSecond = try context.fetch(FetchDescriptor<Medication>()).count

        XCTAssertEqual(countAfterFirst, countAfterSecond)
    }

    func testSeedIncludesTodaysDoseLogs() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        SeedData.seedIfEmpty(context)
        try context.save()

        let cal = Calendar.current
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        let todays = logs.filter { cal.isDate($0.scheduledDate, inSameDayAs: .now) }
        XCTAssertGreaterThanOrEqual(todays.count, 2)
        XCTAssertTrue(todays.contains { $0.status == DoseStatus.taken.rawValue })
        XCTAssertTrue(todays.contains { $0.status == DoseStatus.skipped.rawValue })
    }

    func testSeedIncludesSwapChainWithContinuousJournal() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        SeedData.seedIfEmpty(context)
        try context.save()

        let atenolol = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Atenolol" })).first)
        // Discontinued predecessor that was swapped to the active Metoprolol.
        XCTAssertFalse(atenolol.isActive)
        XCTAssertEqual(atenolol.successor?.name, "Metoprolol")

        // The merged lineage timeline (anchored on the active Metoprolol) reads
        // across both drugs and includes the swap and a free-form note.
        let metoprolol = try XCTUnwrap(atenolol.successor)
        let events = MedicationLineage.events(from: metoprolol)
        let types = Set(events.map { $0.event.eventType })
        XCTAssertTrue(types.contains(MedChangeType.swapped.rawValue))
        XCTAssertTrue(types.contains(MedChangeType.note.rawValue))
        // The swap-born Metoprolol's `added` is suppressed; the line's only
        // `added` belongs to the root, Atenolol.
        let addedOwners = events
            .filter { $0.event.eventType == MedChangeType.added.rawValue }
            .map { $0.owningMed.name }
        XCTAssertEqual(addedOwners, ["Atenolol"])
    }

    func testSeedIncludesHealthMetricsAcrossKinds() throws {
        let container = try ModelTestSupport.makeContainer()
        SeedData.seedIfEmpty(container.mainContext)
        let metrics = try container.mainContext.fetch(FetchDescriptor<HealthMetric>())
        XCTAssertGreaterThanOrEqual(metrics.count, 4)
        let kinds = Set(metrics.map(\.metricKind))
        XCTAssertTrue(kinds.contains(.weight))
        XCTAssertTrue(kinds.contains(.bloodPressure))
        XCTAssertTrue(metrics.allSatisfy { !$0.healthKitSynced })   // seed never touches Health
    }
}

