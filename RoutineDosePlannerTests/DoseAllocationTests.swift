import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct DoseAllocationTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    private func medWithRoutines(target: Double, quantities: [Double]) -> Medication {
        let med = Medication(name: "Test", strengthValue: 30, strengthUnit: "mg",
                             dailyDoseTarget: target)
        context.insert(med)
        for q in quantities {
            let routine = Routine(name: "B")
            context.insert(routine)
            context.insert(RoutineItem(quantity: q, medication: med, routine: routine))
        }
        return med
    }

    @Test func allocatedSumsAllRoutineQuantities() {
        let med = medWithRoutines(target: 2, quantities: [1.0, 0.5])
        #expect(DoseAllocation.allocated(med) == 1.5)
    }

    @Test func remainingIsTargetMinusAllocatedClampedAtZero() {
        let under = medWithRoutines(target: 2, quantities: [0.5])
        #expect(DoseAllocation.remaining(under) == 1.5)
        let over = medWithRoutines(target: 1, quantities: [1.0, 0.5])
        #expect(DoseAllocation.remaining(over) == 0)
    }

    @Test func statusReflectsUnderFullOver() {
        #expect(DoseAllocation.status(medWithRoutines(target: 2, quantities: [0.5])) == .under)
        #expect(DoseAllocation.status(medWithRoutines(target: 2, quantities: [1.0, 1.0])) == .full)
        #expect(DoseAllocation.status(medWithRoutines(target: 1, quantities: [1.0, 0.5])) == .over)
    }

    @Test func derivedStrengthMultipliesValueByCount() {
        let med = medWithRoutines(target: 2, quantities: [1.0, 1.0])  // 30mg x 2
        #expect(DoseAllocation.allocatedStrength(med) == 60)
        #expect(DoseAllocation.targetStrength(med) == 60)
    }

    @Test func needsAttentionTrueWhenUnderAndScheduled() {
        #expect(DoseAllocation.needsAttention(medWithRoutines(target: 2, quantities: [0.5])))
    }

    @Test func needsAttentionFalseWhenFull() {
        #expect(!DoseAllocation.needsAttention(medWithRoutines(target: 2, quantities: [1.0, 1.0])))
    }

    @Test func needsAttentionFalseForPRN() {
        let med = Medication(name: "PRN", strengthValue: 500, strengthUnit: "mg",
                             dailyDoseTarget: 1, isPRN: true)
        context.insert(med)
        #expect(!DoseAllocation.needsAttention(med))
    }

    @Test func needsAttentionFalseForDiscontinued() {
        let med = medWithRoutines(target: 2, quantities: [0.5])
        med.isActive = false
        #expect(!DoseAllocation.needsAttention(med))
    }
}
