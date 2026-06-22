import SwiftUI
import SwiftData

/// Guided instructions change for one membership; reason required.
struct ChangeInstructionsSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectionID: PersistentIdentifier?
    @State private var instructions = ""
    @State private var reason = ""

    private var selection: RoutineItem? {
        guard let selectionID else { return nil }
        return (medication.routineItems ?? []).first { $0.persistentModelID == selectionID }
    }

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Membership") {
                    Picker("Routine", selection: $selectionID) {
                        ForEach(medication.routineItems ?? []) { item in
                            Text(item.routine?.name ?? "—")
                                .tag(PersistentIdentifier?.some(item.persistentModelID))
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
                selectionID = (medication.routineItems ?? []).first?.persistentModelID
                instructions = selection?.instructionsOverride ?? ""
            }
            .onChange(of: selectionID) { _, newID in
                instructions = selection?.instructionsOverride ?? ""
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
