import SwiftData
import XCTest
@testable import PillDaddy

@MainActor
final class DoseLogServicePRNTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelTestSupport.makeContainer()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil; container = nil
        try await super.tearDown()
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    func testLogPRNCreatesBatchItemNilRowAndIsRepeatable() throws {
        let med = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(med)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 2.0, note: "headache", in: context)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)

        let all = try logs()
        XCTAssertEqual(all.count, 2)                  // each PRN dose is its own row
        XCTAssertTrue(all.allSatisfy { $0.batchItem == nil })
        XCTAssertEqual(all.first?.snapshotMedName, "Acetaminophen")
        XCTAssertEqual(Set(all.map { $0.quantity }), [1.0, 2.0])
    }

    func testDeletePRNLogRemovesExactlyOne() throws {
        let med = Medication(name: "Acetaminophen", strength: "500mg", isPRN: true)
        context.insert(med)
        let first = DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)

        DoseLogService.deletePRNLog(first, in: context)
        XCTAssertEqual(try logs().count, 1)
    }
}
