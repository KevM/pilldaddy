import SwiftUI
import SwiftData

/// Guided dose change: edit strength and per-batch quantities; reason required.
struct ChangeDoseSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var strengthValue = 0.0
    @State private var strengthUnit = "mg"
    @State private var target = 1.0
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @State private var reason = ""

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var prospectiveTotal: Double {
        (medication.batchItems ?? []).reduce(0.0) { sum, item in
            sum + (quantities[item.persistentModelID] ?? item.quantity)
        }
    }

    private var overAllocated: Bool {
        prospectiveTotal > target + 0.0001
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New dose") {
                    HStack {
                        TextField("Strength", value: $strengthValue, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("Unit", text: $strengthUnit)
                            .frame(maxWidth: 80)
                    }

                    DoseQuantityField(title: "Doses per day", value: $target)

                    ForEach(medication.batchItems ?? []) { item in
                        let id = item.persistentModelID
                        DoseQuantityField(
                            title: item.batch?.name ?? "—",
                            value: Binding(get: { quantities[id] ?? item.quantity },
                                           set: { quantities[id] = $0 }))
                    }

                    Text("\(DoseFormat.qty(prospectiveTotal)) of \(DoseFormat.qty(target))/day · \(DoseFormat.qty(prospectiveTotal * strengthValue)) of \(DoseFormat.qty(target * strengthValue)) \(strengthUnit)")
                        .font(.caption)
                        .foregroundStyle(overAllocated ? .red : .secondary)
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
                    Button("Save") { save() }
                        .disabled(!reasonValid || overAllocated)
                }
            }
            .onAppear {
                strengthValue = medication.strengthValue
                strengthUnit = medication.strengthUnit
                target = medication.dailyDoseTarget
            }
        }
    }

    private func save() {
        let changes = (medication.batchItems ?? []).compactMap {
            item -> (item: BatchItem, quantity: Double)? in
            guard let q = quantities[item.persistentModelID] else { return nil }
            return (item, q)
        }
        try? MedicationService.changeDose(
            medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
            newDailyDoseTarget: target, newQuantities: changes,
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
