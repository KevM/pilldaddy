import Foundation
import SwiftData
import Testing
@testable import RoutineDosePlanner

@MainActor
struct RoutineQueryTests {

    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        self.container = try ModelTestSupport.makeContainer()
        self.context = container.mainContext
    }

    @Test
    func testActiveRoutineGroupsExcludeDiscontinuedAndPRN() throws {
        let blue = Routine(name: "Blue")
        context.insert(blue)

        let active = try MedicationService.addMedication(
            name: "Active", strengthValue: 10, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        _ = active

        let discontinued = try MedicationService.addMedication(
            name: "Stopped", strengthValue: 10, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "",
            placements: [(routine: blue, quantity: 1.0)], reason: "", in: context)
        try MedicationService.discontinue(discontinued, reason: "stop", in: context)

        let groups = try RoutineQuery.activeRoutineGroups(in: context)
        #expect(groups.count == 1)
        #expect(groups.first?.items.count == 1)
        #expect(groups.first?.items.first?.medication?.name == "Active")
    }

    @Test
    func testActivePRNMedsReturnsOnlyActivePRN() throws {
        _ = try MedicationService.addMedication(
            name: "Tylenol", strengthValue: 500, strengthUnit: "mg", form: "tablet",
            isPRN: true, notes: "", placements: [], reason: "", in: context)
        let scheduled = try MedicationService.addMedication(
            name: "Scheduled", strengthValue: 1, strengthUnit: "mg", form: "tablet",
            isPRN: false, notes: "", placements: [], reason: "", in: context)
        _ = scheduled

        let prn = try RoutineQuery.activePRNMeds(in: context)
        #expect(prn.map(\.name) == ["Tylenol"])
    }

    @Test
    func testActiveRoutineGroupsSortByTimeOfDay() throws {
        func at(_ h: Int) -> Date { Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)! }
        
        let evening = Routine(name: "Evening", timeOfDay: at(19))
        let morning = Routine(name: "Morning", timeOfDay: at(7))
        let midday = Routine(name: "Midday", timeOfDay: at(12))
        
        context.insert(evening)
        context.insert(morning)
        context.insert(midday)
        try context.save()

        let names = try RoutineQuery.activeRoutineGroups(in: context).map { $0.routine.name }
        #expect(names == ["Morning", "Midday", "Evening"])
    }
}

