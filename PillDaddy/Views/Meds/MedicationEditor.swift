import SwiftUI
import SwiftData

/// Add a new medication (with inline batch assignment + optional reason) or edit
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
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var batches: [Batch]

    @State private var name = ""
    @State private var strength = ""
    @State private var form = "tablet"
    @State private var notes = ""
    @State private var isPRN = false
    @State private var reason = ""
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var quantities: [PersistentIdentifier: Double] = [:]

    private var isAdd: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    if isAdd {
                        TextField("Strength (e.g. 30mg)", text: $strength)
                    }
                    TextField("Form (e.g. tablet)", text: $form)
                    Toggle("As needed (PRN)", isOn: $isPRN)
                    TextField("General notes", text: $notes, axis: .vertical)
                }

                if isAdd && !isPRN {
                    Section("Add to batches") {
                        if batches.isEmpty {
                            Text("No batches yet — add one from the Meds tab.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(batches) { batch in
                            batchAssignRow(batch)
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
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private func batchAssignRow(_ batch: Batch) -> some View {
        let id = batch.persistentModelID
        let isOn = selected.contains(id)
        VStack(alignment: .leading) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { selected.insert(id); quantities[id] = quantities[id] ?? 1.0 }
                    else { selected.remove(id) }
                })) {
                HStack {
                    Circle().fill(Color(hex: batch.colorHex)).frame(width: 12, height: 12)
                    Text(batch.name.isEmpty ? "Batch" : batch.name)
                    Spacer()
                    Text(batch.timeOfDay, style: .time)
                        .foregroundStyle(.secondary)
                }
            }
            if isOn {
                Stepper(value: Binding(
                    get: { quantities[id] ?? 1.0 },
                    set: { quantities[id] = $0 }),
                    in: 0.5...20, step: 0.5) {
                    Text("Quantity: \(DoseFormat.qty(quantities[id] ?? 1.0))")
                }
            }
        }
    }

    private func load() {
        guard case .edit(let med) = mode else { return }
        name = med.name
        strength = med.strength
        form = med.form
        notes = med.generalNotes
        isPRN = med.isPRN
    }

    private func save() {
        switch mode {
        case .add:
            let placements: [(batch: Batch, quantity: Double)] = isPRN ? [] :
                batches
                    .filter { selected.contains($0.persistentModelID) }
                    .map { ($0, quantities[$0.persistentModelID] ?? 1.0) }
            MedicationService.addMedication(
                name: name, strength: strength, form: form,
                isPRN: isPRN, notes: notes, placements: placements,
                reason: reason, in: context)
        case .edit(let med):
            let wasScheduled = !(med.batchItems ?? []).isEmpty
            med.name = name
            med.form = form
            med.generalNotes = notes
            if isPRN && wasScheduled {
                for item in med.batchItems ?? [] { context.delete(item) }
            }
            med.isPRN = isPRN
            try? context.save()
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    MedicationEditor(mode: .add)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
