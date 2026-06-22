import SwiftUI
import SwiftData

/// Guided dose change: edit strength and per-routine quantities; reason required.
struct ChangeDoseSheet: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var strengthValue = 0.0
    @State private var strengthUnit = "mg"
    @State private var target = 1.0
    @State private var quantities: [PersistentIdentifier: Double] = [:]
    @State private var reason = ""
    @State private var errorMessage: String?

    private var reasonValid: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var prospectiveTotal: Double {
        (medication.routineItems ?? []).reduce(0.0) { sum, item in
            sum + (quantities[item.persistentModelID] ?? item.quantity)
        }
    }

    private var overAllocated: Bool {
        DoseAllocation.isOverTarget(allocated: prospectiveTotal, target: target)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New dose") {
                    StrengthInputField(value: $strengthValue, unit: $strengthUnit)

                    DoseQuantityField(title: "Doses per day", value: $target)

                    ForEach(medication.routineItems ?? []) { item in
                        let id = item.persistentModelID
                        DoseQuantityField(
                            title: item.routine?.name ?? "—",
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

    private func save() {
        let placements: [(routine: Routine, quantity: Double)] =
            (medication.routineItems ?? []).compactMap { item in
                guard let routine = item.routine else { return nil }
                return (routine, quantities[item.persistentModelID] ?? item.quantity)
            }
        do {
            try MedicationService.changeDose(
                medication, newStrengthValue: strengthValue, newStrengthUnit: strengthUnit,
                newDailyDoseTarget: target, placements: placements,
                reason: reason, in: context)
            dismiss()
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let doseError = error as? DoseAllocationError {
            switch doseError {
            case .exceedsDailyTarget:
                return "Total allocation across routines cannot exceed the daily dose target."
            }
        } else if let serviceError = error as? MedicationServiceError {
            switch serviceError {
            case .reasonRequired:
                return "A reason is required to change the dose."
            }
        }
        return error.localizedDescription
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return ChangeDoseSheet(medication: PreviewSupport.firstMedication(container))
        .modelContainer(container)
}
#endif
