import SwiftUI
import SwiftData

/// A small commit-or-cancel sheet to append a free-form note to a medication's
/// journal. Matches the ChangeDoseSheet / LifecycleReasonSheet pattern.
struct AddNoteSheet: View {
    let medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("What happened, and why?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Add note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? MedicationService.addNote(medication, text: text, in: context)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return AddNoteSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
