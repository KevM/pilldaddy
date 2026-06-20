import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class MedicationLineageTests: XCTestCase {

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

    /// Builds A → B → C and returns the three meds in chain order.
    private func makeChain() -> (a: Medication, b: Medication, c: Medication) {
        let a = Medication(name: "Atenolol", strength: "25mg")
        let b = Medication(name: "Metoprolol", strength: "30mg")
        let c = Medication(name: "Bisoprolol", strength: "5mg")
        context.insert(a); context.insert(b); context.insert(c)
        a.successor = b
        b.successor = c
        return (a, b, c)
    }

    func testOrderedFromMidChainReturnsWholeLineOldestFirst() {
        let chain = makeChain()
        let line = MedicationLineage.ordered(from: chain.b)
        XCTAssertEqual(line.map(\.name), ["Atenolol", "Metoprolol", "Bisoprolol"])
    }

    func testOrderedFromTipReturnsWholeLine() {
        let chain = makeChain()
        let line = MedicationLineage.ordered(from: chain.c)
        XCTAssertEqual(line.map(\.name), ["Atenolol", "Metoprolol", "Bisoprolol"])
    }

    func testOrderedForSingleMedIsJustItself() {
        let med = Medication(name: "Vitamin D", strength: "1000 IU")
        context.insert(med)
        XCTAssertEqual(MedicationLineage.ordered(from: med).map(\.name), ["Vitamin D"])
    }

    func testOrderedTerminatesOnCycle() {
        let a = Medication(name: "A", strength: "1")
        let b = Medication(name: "B", strength: "1")
        context.insert(a); context.insert(b)
        a.successor = b
        b.successor = a   // malformed cycle
        let line = MedicationLineage.ordered(from: a)
        // Must terminate and visit each med at most once.
        XCTAssertEqual(Set(line.map(\.name)), ["A", "B"])
        XCTAssertEqual(line.count, 2)
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

    func testEventsMergeChainNewestFirst() {
        let chain = makeChain()
        addEvent(.added, to: chain.a, daysAgo: 150)
        addEvent(.swapped, to: chain.a, daysAgo: 100)
        addEvent(.swapped, to: chain.b, daysAgo: 60)
        addEvent(.doseChanged, to: chain.c, daysAgo: 30)

        let events = MedicationLineage.events(from: chain.c)
        // Newest first; the suppressed `added` on B/C never existed here.
        XCTAssertEqual(events.map { MedChangeType(rawValue: $0.event.eventType) },
                       [.doseChanged, .swapped, .swapped, .added])
    }

    func testEventsSuppressAddedOnSwapBornMeds() {
        let chain = makeChain()
        addEvent(.added, to: chain.a, daysAgo: 100)   // root: kept
        addEvent(.added, to: chain.b, daysAgo: 60)    // swap-born: suppressed
        addEvent(.added, to: chain.c, daysAgo: 30)    // swap-born: suppressed

        let events = MedicationLineage.events(from: chain.c)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.owningMed.name, "Atenolol")
    }

    func testEventsMarkAnchorAndSuccessorName() {
        let chain = makeChain()
        addEvent(.swapped, to: chain.a, daysAgo: 100)   // owned by Atenolol → successor Metoprolol
        addEvent(.doseChanged, to: chain.b, daysAgo: 60) // anchor

        let events = MedicationLineage.events(from: chain.b)
        let swap = try! XCTUnwrap(events.first { $0.event.eventType == MedChangeType.swapped.rawValue })
        XCTAssertEqual(swap.successorName, "Metoprolol")
        XCTAssertFalse(swap.isAnchor)

        let dose = try! XCTUnwrap(events.first { $0.event.eventType == MedChangeType.doseChanged.rawValue })
        XCTAssertTrue(dose.isAnchor)
    }
}
