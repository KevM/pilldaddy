import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct MedicationLineageTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    /// Builds A → B → C and returns the three meds in chain order.
    private func makeChain() -> (a: Medication, b: Medication, c: Medication) {
        let a = Medication(name: "Atenolol", strengthValue: 25, strengthUnit: "mg", dailyDoseTarget: 1.0)
        let b = Medication(name: "Metoprolol", strengthValue: 30, strengthUnit: "mg", dailyDoseTarget: 1.0)
        let c = Medication(name: "Bisoprolol", strengthValue: 5, strengthUnit: "mg", dailyDoseTarget: 1.0)
        context.insert(a); context.insert(b); context.insert(c)
        a.successor = b
        b.successor = c
        return (a, b, c)
    }

    @Test
    func testOrderedFromMidChainReturnsWholeLineOldestFirst() {
        let chain = makeChain()
        let line = MedicationLineage.ordered(from: chain.b)
        #expect(line.map(\.name) == ["Atenolol", "Metoprolol", "Bisoprolol"])
    }

    @Test
    func testOrderedFromTipReturnsWholeLine() {
        let chain = makeChain()
        let line = MedicationLineage.ordered(from: chain.c)
        #expect(line.map(\.name) == ["Atenolol", "Metoprolol", "Bisoprolol"])
    }

    @Test
    func testOrderedForSingleMedIsJustItself() {
        let med = Medication(name: "Vitamin D", strengthValue: 1000, strengthUnit: "IU", dailyDoseTarget: 1.0)
        context.insert(med)
        #expect(MedicationLineage.ordered(from: med).map(\.name) == ["Vitamin D"])
    }

    @Test
    func testOrderedTerminatesOnCycle() {
        let a = Medication(name: "A", strengthValue: 1, strengthUnit: "", dailyDoseTarget: 1.0)
        let b = Medication(name: "B", strengthValue: 1, strengthUnit: "", dailyDoseTarget: 1.0)
        context.insert(a); context.insert(b)
        a.successor = b
        b.successor = a   // malformed cycle
        let line = MedicationLineage.ordered(from: a)
        // Must terminate and visit each med at most once.
        #expect(Set(line.map(\.name)) == ["A", "B"])
        #expect(line.count == 2)
    }

    /// Helper: attach an event with an explicit timestamp.
    private func addEvent(_ type: MedChangeType, to med: Medication,
                           daysAgo: Int, reasoning: String = "",
                           oldValue: String = "", newValue: String = "") {
        let ts = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        context.insert(MedicationChangeEvent(
            timestamp: ts, type: type, reasoning: reasoning,
            oldValue: oldValue, newValue: newValue, medication: med))
    }

    @Test
    func testEventsMergeChainNewestFirst() {
        let chain = makeChain()
        addEvent(.added, to: chain.a, daysAgo: 150)
        addEvent(.swapped, to: chain.a, daysAgo: 100)
        addEvent(.swapped, to: chain.b, daysAgo: 60)
        addEvent(.doseChanged, to: chain.c, daysAgo: 30)

        let events = MedicationLineage.events(from: chain.c)
        // Newest first; the suppressed `added` on B/C never existed here.
        #expect(events.map { MedChangeType(rawValue: $0.event.eventType) } ==
               [.doseChanged, .swapped, .swapped, .added])
    }

    @Test
    func testEventsSuppressAddedOnSwapBornMeds() {
        let chain = makeChain()
        addEvent(.added, to: chain.a, daysAgo: 100)   // root: kept
        addEvent(.added, to: chain.b, daysAgo: 60)    // swap-born: suppressed
        addEvent(.added, to: chain.c, daysAgo: 30)    // swap-born: suppressed

        let events = MedicationLineage.events(from: chain.c)
        #expect(events.count == 1)
        #expect(events.first?.owningMed.name == "Atenolol")
    }

    @Test
    func testEventsMarkAnchorAndSuccessorName() throws {
        let chain = makeChain()
        addEvent(.swapped, to: chain.a, daysAgo: 100)   // owned by Atenolol → successor Metoprolol
        addEvent(.doseChanged, to: chain.b, daysAgo: 60) // anchor

        let events = MedicationLineage.events(from: chain.b)
        let swap = try #require(events.first { $0.event.eventType == MedChangeType.swapped.rawValue })
        #expect(swap.successorName == "Metoprolol")
        #expect(!swap.isAnchor)

        let dose = try #require(events.first { $0.event.eventType == MedChangeType.doseChanged.rawValue })
        #expect(dose.isAnchor)
    }
}

