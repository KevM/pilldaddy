import SwiftUI
import SwiftData

/// Records a single ad-hoc PRN dose: time (default now), quantity, optional note.
struct PRNLogSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var takenAt = Date.now
    @State private var quantity = 1.0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Dose") {
                    DatePicker("Time", selection: $takenAt)
                    Stepper("Quantity: \(DoseFormat.qty(quantity))",
                            value: $quantity, in: 0.5...20, step: 0.5)
                }
                Section("Note (optional)") {
                    TextField("e.g. for headache", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log \(medication.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        DoseLogService.logPRN(medication, takenAt: takenAt,
                                              quantity: quantity, note: note, in: context)
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return PRNLogSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
