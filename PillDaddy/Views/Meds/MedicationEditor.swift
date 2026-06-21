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

    private var assignedTotal: Double {
        selected.reduce(0.0) { $0 + (quantities[$1] ?? 1.0) }
    }

    private var saveBlocked: Bool {
        guard isAdd, !isPRN else { return false }
        return dailyDoseTarget <= 0 || DoseAllocation.isOverTarget(allocated: assignedTotal, target: dailyDoseTarget)
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
                        DoseQuantityField(title: "Doses per day", value: $dailyDoseTarget)
                    }
                    TextField("General notes", text: $notes, axis: .vertical)
                }

                if isAdd && !isPRN {
                    Section {
                        if routines.isEmpty {
                            Text("No routines yet — add one from the Meds tab.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(routines) { routine in
                            batchAssignRow(routine)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add to routines")
                            let isOver = DoseAllocation.isOverTarget(allocated: assignedTotal, target: dailyDoseTarget)
                            Text("\(DoseFormat.qty(assignedTotal)) of \(DoseFormat.qty(dailyDoseTarget))/day allocated (\(DoseFormat.qty(assignedTotal * strengthValue)) of \(DoseFormat.qty(dailyDoseTarget * strengthValue)) \(strengthUnit))")
                                .font(.caption)
                                .foregroundStyle(isOver ? .red : .secondary)
                        }
                    }
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

    @ViewBuilder
    private func batchAssignRow(_ routine: Routine) -> some View {
        let id = routine.persistentModelID
        let isOn = selected.contains(id)
        VStack(alignment: .leading) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { selected.insert(id); quantities[id] = quantities[id] ?? 1.0 }
                    else { selected.remove(id) }
                })) {
                HStack {
                    Circle().fill(Color(hex: routine.colorHex)).frame(width: 12, height: 12)
                    Text(routine.name.isEmpty ? "Routine" : routine.name)
                    Spacer()
                    Text(routine.timeOfDay, style: .time)
                        .foregroundStyle(.secondary)
                }
            }
            if isOn {
                DoseQuantityField(
                    title: "Quantity",
                    value: Binding(get: { quantities[id] ?? 1.0 },
                                   set: { quantities[id] = $0 }),
                    range: 0.5...20, step: 0.5)
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
                    isPRN: isPRN, notes: notes, dailyDoseTarget: dailyDoseTarget, placements: placements,
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
