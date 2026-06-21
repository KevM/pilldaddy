import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct SeedDataTests {
    @Test
    func testSeedPopulatesWorkedExampleRoutines() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()

        // Metoprolol exists in two routines at 1.0 and 0.5
        let metoprolol = try #require(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Metoprolol" })).first)
        #expect(metoprolol.routineItems?.count == 2)
        #expect((metoprolol.routineItems ?? []).map(\.quantity).sorted() == [0.5, 1.0])

        // At least one PRN med
        let prnMeds = try context.fetch(FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isPRN == true }))
        #expect(prnMeds.count >= 1)

        // At least one change-event in the history
        let events = try context.fetch(FetchDescriptor<MedicationChangeEvent>())
        #expect(events.count >= 1)
    }

    @Test
    func testSeedIsIdempotent() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext

        SeedData.seedIfEmpty(context)
        try context.save()
        let countAfterFirst = try context.fetch(FetchDescriptor<Medication>()).count

        SeedData.seedIfEmpty(context)   // second call must be a no-op
        try context.save()
        let countAfterSecond = try context.fetch(FetchDescriptor<Medication>()).count

        #expect(countAfterFirst == countAfterSecond)
    }

    @Test
    func testSeedIncludesTodaysDoseLogs() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        SeedData.seedIfEmpty(context)
        try context.save()

        let cal = Calendar.current
        let logs = try context.fetch(FetchDescriptor<DoseLog>())
        let todays = logs.filter { cal.isDate($0.scheduledDate, inSameDayAs: .now) }
        #expect(todays.count >= 2)
        #expect(todays.contains { $0.status == DoseStatus.taken.rawValue })
        #expect(todays.contains { $0.status == DoseStatus.skipped.rawValue })
    }

    @Test
    func testSeedIncludesSwapChainWithContinuousJournal() throws {
        let container = try ModelTestSupport.makeContainer()
        let context = container.mainContext
        SeedData.seedIfEmpty(context)
        try context.save()

        let atenolol = try #require(
            try context.fetch(FetchDescriptor<Medication>(
                predicate: #Predicate { $0.name == "Atenolol" })).first)
        // Discontinued predecessor that was swapped to the active Metoprolol.
        #expect(!atenolol.isActive)
        #expect(atenolol.successor?.name == "Metoprolol")

        // The merged lineage timeline (anchored on the active Metoprolol) reads
        // across both drugs and includes the swap and a free-form note.
        let metoprolol = try #require(atenolol.successor)
        let events = MedicationLineage.events(from: metoprolol)
        let types = Set(events.map { $0.event.eventType })
        #expect(types.contains(MedChangeType.swapped.rawValue))
        #expect(types.contains(MedChangeType.note.rawValue))
        // The swap-born Metoprolol's `added` is suppressed; the line's only
        // `added` belongs to the root, Atenolol.
        let addedOwners = events
            .filter { $0.event.eventType == MedChangeType.added.rawValue }
            .map { $0.owningMed.name }
        #expect(addedOwners == ["Atenolol"])
    }

    @Test
    func testSeedIncludesHealthMetricsAcrossKinds() throws {
        let container = try ModelTestSupport.makeContainer()
        SeedData.seedIfEmpty(container.mainContext)
        let metrics = try container.mainContext.fetch(FetchDescriptor<HealthMetric>())
        #expect(metrics.count >= 4)
        let kinds = Set(metrics.map(\.metricKind))
        #expect(kinds.contains(.weight))
        #expect(kinds.contains(.bloodPressure))
        #expect(metrics.allSatisfy { !$0.healthKitSynced })   // seed never touches Health
    }
}


