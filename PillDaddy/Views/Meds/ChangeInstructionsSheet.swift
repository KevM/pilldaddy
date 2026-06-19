import SwiftUI
import SwiftData

/// Guided instructions change for one membership; reason required.
struct ChangeInstructionsSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selection: BatchItem?
    @State private var instructions = ""
    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Membership") {
                    Picker("Batch", selection: $selection) {
                        ForEach(medication.batchItems ?? []) { item in
                            Text(item.batch?.name ?? "—").tag(Optional(item))
                        }
                    }
                }
                Section("Instructions") {
                    TextField("e.g. take on empty stomach", text: $instructions, axis: .vertical)
                }
                Section("Reason (required)") {
                    TextField("Why are instructions changing?", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle("Change instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(selection == nil || !reasonValid)
                }
            }
            .onAppear {
                selection = (medication.batchItems ?? []).first
                instructions = selection?.instructionsOverride ?? ""
            }
            .onChange(of: selection) { _, new in
                instructions = new?.instructionsOverride ?? ""
            }
        }
    }

    private func save() {
        guard let item = selection else { return }
        try? MedicationService.changeInstructions(
            item, newInstructions: instructions, reason: reason, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return ChangeInstructionsSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
