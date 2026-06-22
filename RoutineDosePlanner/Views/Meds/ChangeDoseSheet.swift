import SwiftUI
import SwiftData

/// Guided dose change: edit strength and per-routine quantities; reason required.
struct ChangeDoseSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var strengthValue = 0.0
    @State private var strengthUnit = "mg"
    @State private var target = 1.0
    @State private var variesByDay = false
    @State private var weekdayTargets = Array(repeating: 1.0, count: 7)
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var allRoutines: [Routine]

    @State private var selected: Set<PersistentIdentifier> = []
    @State private var reason = ""
    @State private var errorMessage: String?

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedWeekdayTargets: [Double]? {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).perWeekday : nil
    }
    private var resolvedDaily: Double {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).daily : target
    }
    private var overAllocated: Bool {
        let routinesByID = Dictionary(uniqueKeysWithValues: allRoutines.map { ($0.persistentModelID, $0) })
        let placements: [(routine: Routine, quantity: Double)] = selected.compactMap { id in
            guard let routine = routinesByID[id] else { return nil }
            return (routine, quantities[id] ?? 1.0)
        }
        return DoseAllocation.placementsOverTarget(
            daily: resolvedDaily, perWeekday: resolvedWeekdayTargets, placements: placements)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New dose") {
                    StrengthInputField(value: $strengthValue, unit: $strengthUnit)
                    Toggle("Amount varies by day of week", isOn: $variesByDay)
                    if variesByDay {
                        ForEach(1...7, id: \.self) { wd in
                            DoseQuantityField(
                                title: DoseSummaryFormatter.shortWeekdays[wd - 1],
                                value: Binding(
                                    get: { weekdayTargets[wd - 1] },
                                    set: { weekdayTargets[wd - 1] = $0 }),
                                range: 0...20, step: 0.5)
                        }
                    } else {
                        DoseQuantityField(title: "Doses per day", value: $target)
                    }
                }
                if !medication.isPRN {
                    RoutineAllocationSection(
                        title: "Allocate across routines",
                        routines: allRoutines,
                        selected: $selected,
                        quantities: $quantities,
                        target: resolvedDaily,
                        strengthValue: strengthValue,
                        strengthUnit: strengthUnit)
                }
                Section("Reason (required)") {
                    TextField("Why is the dose changing?", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle("Change dose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!reasonValid || overAllocated)
                }
            }
            .onAppear {
                strengthValue = medication.strengthValue
                strengthUnit = medication.strengthUnit
                target = medication.dailyDoseTarget
                variesByDay = medication.hasVariableSchedule
                weekdayTargets = WeekdayDoseTargets.expand(
                    daily: medication.dailyDoseTarget, perWeekday: medication.weekdayDoseTargets)
                for item in medication.routineItems ?? [] {
                    guard let routine = item.routine else { continue }
                    let id = routine.persistentModelID
                    selected.insert(id)
                    quantities[id] = item.quantity
                }
            }
            .alert("Cannot Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    private func save() {
        let routinesByID = Dictionary(uniqueKeysWithValues:
            allRoutines.map { ($0.persistentModelID, $0) })
        let placements: [(routine: Routine, quantity: Double)] = selected.compactMap { id in
            guard let routine = routinesByID[id] else { return nil }
            return (routine, quantities[id] ?? 1.0)
        }
        do {
            try MedicationService.changeDose(
                medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
                newDailyDoseTarget: resolvedDaily, newWeekdayDoseTargets: resolvedWeekdayTargets,
                placements: placements, reason: reason, in: context)
            dismiss()
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let doseError = error as? DoseAllocationError {
            switch doseError {
            case .exceedsDailyTarget:
                return "Total allocation across routines cannot exceed the daily dose target."
            }
        } else if let serviceError = error as? MedicationServiceError {
            switch serviceError {
            case .reasonRequired:
                return "A reason is required to change the dose."
            }
        }
        return error.localizedDescription
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return ChangeDoseSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
