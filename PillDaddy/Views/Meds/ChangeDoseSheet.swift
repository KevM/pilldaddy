import SwiftUI
import SwiftData

/// Guided dose change: edit strength and per-batch quantities; reason required.
struct ChangeDoseSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var strength = ""
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New dose") {
                    TextField("Strength", text: $strength)
                    ForEach(medication.batchItems ?? []) { item in
                        let id = item.persistentModelID
                        Stepper(value: Binding(
                            get: { quantities[id] ?? item.quantity },
                            set: { quantities[id] = $0 }),
                            in: 0.5...20, step: 0.5) {
                            Text("\(item.batch?.name ?? "—"): \(DoseFormat.qty(quantities[id] ?? item.quantity))")
                        }
                    }
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
                    Button("Save") { save() }.disabled(!reasonValid)
                }
            }
            .onAppear { strength = medication.strength }
        }
    }

    private func save() {
        let changes = (medication.batchItems ?? []).compactMap {
            item -> (item: BatchItem, quantity: Double)? in
            guard let q = quantities[item.persistentModelID] else { return nil }
            return (item, q)
        }
        try? MedicationService.changeDose(
            medication, newStrength: strength, newQuantities: changes,
            reason: reason, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return ChangeDoseSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
