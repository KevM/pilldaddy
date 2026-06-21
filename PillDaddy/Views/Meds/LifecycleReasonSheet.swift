import SwiftUI
import SwiftData

/// Reason-gated discontinue / reactivate flow.
struct LifecycleReasonSheet: View {
    @Bindable var medication: Medication
    let reactivating: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(reactivating
                         ? "Reactivating restores this medication to the active routines."
                         : "Discontinuing removes this medication from the active routines. Its full history is kept.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Reason (required)") {
                    TextField("Reason", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle(reactivating ? "Reactivate" : "Discontinue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(reactivating ? "Reactivate" : "Discontinue", role: reactivating ? .none : .destructive) {
                        save()
                    }
                    .disabled(!reasonValid)
                }
            }
        }
    }

    private func save() {
        if reactivating {
            try? MedicationService.reactivate(medication, reason: reason, in: context)
        } else {
            try? MedicationService.discontinue(medication, reason: reason, in: context)
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return LifecycleReasonSheet(medication: PreviewSupport.firstMedication(container), reactivating: false)
        .modelContainer(container)
}
#endif
