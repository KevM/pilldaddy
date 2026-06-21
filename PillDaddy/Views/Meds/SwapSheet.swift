import SwiftUI
import SwiftData

/// Guided atomic swap: name the replacement, optionally inherit the old drug's
/// schedule, give a required reason. The old drug is auto-discontinued on save.
struct SwapSheet: View {
    @Bindable var oldMed: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var strengthValue = 0.0
    @State private var strengthUnit = "mg"
    @State private var form = "tablet"
    @State private var inheritSchedule = true
    @State private var reason = ""

    private var canSave: Bool {
        !name.isEmpty && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Replacement drug") {
                    TextField("Name", text: $name)
                    StrengthInputField(value: $strengthValue, unit: $strengthUnit)
                    TextField("Form", text: $form)
                }
                Section("Schedule") {
                    Toggle("Keep \(oldMed.name)'s schedule", isOn: $inheritSchedule)
                    if inheritSchedule {
                        ForEach(oldMed.routineItems ?? []) { item in
                            HStack {
                                Text(item.routine?.name ?? "—")
                                Spacer()
                                Text("\(DoseFormat.qty(item.quantity)) \(oldMed.form)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Reason (required)") {
                    TextField("Why the swap?", text: $reason, axis: .vertical)
                }
            }
            .navigationTitle("Swap medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save swap") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        _ = try? MedicationService.swap(
            oldMed, newName: name, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit, newForm: form,
            inheritSchedule: inheritSchedule, reason: reason, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return SwapSheet(oldMed: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
