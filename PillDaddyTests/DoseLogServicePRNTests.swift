import Foundation
import SwiftData
import Testing
@testable import PillDaddy

@MainActor
struct DoseLogServicePRNTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    private func logs() throws -> [DoseLog] { try context.fetch(FetchDescriptor<DoseLog>()) }

    @Test
    func testLogPRNCreatesRoutineItemNilRowAndIsRepeatable() throws {
        let med = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg", dailyDoseTarget: 1.0, isPRN: true)
        context.insert(med)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 2.0, note: "headache", in: context)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)

        let all = try logs()
        #expect(all.count == 2)                  // each PRN dose is its own row
        #expect(all.allSatisfy { $0.routineItem == nil })
        #expect(all.first?.snapshotMedName == "Acetaminophen")
        #expect(Set(all.map { $0.quantity }) == [1.0, 2.0])
    }

    @Test
    func testDeletePRNLogRemovesExactlyOne() throws {
        let med = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg", dailyDoseTarget: 1.0, isPRN: true)
        context.insert(med)
        let first = DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)

        DoseLogService.deletePRNLog(first, in: context)
        #expect(try logs().count == 1)
    }

    @Test
    func testLogPRNSetsIsPRNFlag() throws {
        let med = Medication(name: "Acetaminophen", strengthValue: 500, strengthUnit: "mg",
                             dailyDoseTarget: 1.0, isPRN: true)
        context.insert(med)
        DoseLogService.logPRN(med, takenAt: .now, quantity: 1.0, note: "", in: context)
        let all = try logs()
        #expect(all.allSatisfy { $0.isPRN })
    }
}

