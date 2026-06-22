import SwiftUI
import SwiftData

/// Add a new medication (with inline routine assignment + optional reason) or edit
/// an existing one's non-clinical details. Strength/dose changes go through the
/// guided Change-dose flow, not here.
struct MedicationEditor: View {
    enum Mode {
        case add
        case edit(Medication)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var routines: [Routine]

    @State private var name = ""
    @State private var strengthValue = 0.0
    @State private var strengthUnit = "mg"
    @State private var dailyDoseTarget = 1.0
    @State private var variesByDay = false
    @State private var weekdayTargets = Array(repeating: 1.0, count: 7)
    @State private var form = "tablet"
    @State private var notes = ""
    @State private var isPRN = false
    @State private var reason = ""
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @State private var errorMessage: String?

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    private var resolvedWeekdayTargets: [Double]? {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).perWeekday : nil
    }
    private var resolvedDaily: Double {
        variesByDay ? WeekdayDoseTargets.collapse(weekdayTargets).daily : dailyDoseTarget
    }
    private var saveBlocked: Bool {
        guard isAdd, !isPRN else { return false }
        if resolvedWeekdayTargets == nil && resolvedDaily <= 0 { return true }
        let placements = routines
            .filter { selected.contains($0.persistentModelID) }
            .map { (routine: $0, quantity: quantities[$0.persistentModelID] ?? 1.0) }
        return DoseAllocation.placementsOverTarget(
            daily: resolvedDaily, perWeekday: resolvedWeekdayTargets, placements: placements)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    if isAdd {
                        StrengthInputField(value: $strengthValue, unit: $strengthUnit)
                    }
                    TextField("Form (e.g. tablet)", text: $form)
                    Toggle("As needed (PRN)", isOn: $isPRN)
                    if isAdd && !isPRN {
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
                            DoseQuantityField(title: "Doses per day", value: $dailyDoseTarget)
                        }
                    }
                    TextField("General notes", text: $notes, axis: .vertical)
                }

                if isAdd && !isPRN {
                    RoutineAllocationSection(
                        title: "Add to routines",
                        routines: routines,
                        selected: $selected,
                        quantities: $quantities,
                        target: resolvedDaily,
                        strengthValue: strengthValue,
                        strengthUnit: strengthUnit)
                    Section("Why started? (optional)") {
                        TextField("Reason", text: $reason, axis: .vertical)
                    }
                }
            }
            .navigationTitle(isAdd ? "New medication" : "Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || saveBlocked)
                }
            }
            .onAppear(perform: load)
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

    private func load() {
        guard case .edit(let med) = mode else { return }
        name = med.name
        strengthValue = med.strengthValue
        strengthUnit = med.strengthUnit
        form = med.form
        notes = med.generalNotes
        isPRN = med.isPRN
    }

    private func save() {
        switch mode {
        case .add:
            let placements: [(routine: Routine, quantity: Double)] = isPRN ? [] :
                routines
                    .filter { selected.contains($0.persistentModelID) }
                    .map { ($0, quantities[$0.persistentModelID] ?? 1.0) }
            do {
                try MedicationService.addMedication(
                    name: name, strengthValue: strengthValue, strengthUnit: strengthUnit, form: form,
                    isPRN: isPRN, notes: notes, dailyDoseTarget: resolvedDaily,
                    weekdayDoseTargets: resolvedWeekdayTargets, placements: placements,
                    reason: reason, in: context)
                dismiss()
            } catch {
                errorMessage = errorMessage(for: error)
            }
        case .edit(let med):
            let wasScheduled = !(med.routineItems ?? []).isEmpty
            med.name = name
            med.form = form
            med.generalNotes = notes
            if isPRN && wasScheduled {
                for item in med.routineItems ?? [] { context.delete(item) }
                context.insert(MedicationChangeEvent(
                    type: .doseChanged,
                    reasoning: "Converted medication to PRN (cleared scheduled routines)",
                    medication: med
                ))
            }
            med.isPRN = isPRN
            do {
                try context.save()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let doseError = error as? DoseAllocationError {
            switch doseError {
            case .exceedsDailyTarget:
                return "Total allocation across routines cannot exceed the daily dose target."
            }
        }
        return error.localizedDescription
    }
}

#if DEBUG
#Preview {
    MedicationEditor(mode: .add)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
