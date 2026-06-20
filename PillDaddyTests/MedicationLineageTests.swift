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
}
