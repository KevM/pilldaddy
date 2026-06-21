import SwiftUI
import SwiftData

/// Adds the medication to a batch it is not already in, with an allocation-capped
/// quantity. Routes through `MedicationService.addToBatch`.
struct AddToBatchSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var allBatches: [Routine]

    @State private var selectedBatch: Routine?
    @State private var quantity = 1.0
    @State private var errorMessage: String?

    private var available: [Routine] {
        let present = Set((medication.routineItems ?? []).compactMap { $0.routine?.persistentModelID })
        return allBatches.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if available.isEmpty {
                    Text("This medication is already in every batch.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Routine", selection: $selectedBatch) {
                        Text("Select…").tag(Routine?.none)
                        ForEach(available) { batch in
                            Text(batch.name.isEmpty ? "Routine" : batch.name).tag(Routine?.some(batch))
                        }
                    }
                    DoseQuantityField(
                        title: "Quantity", value: $quantity,
                        range: 0.5...20, step: 0.5,
                        max: DoseAllocation.remaining(medication))
                    Text("\(DoseFormat.qty(DoseAllocation.remaining(medication))) of \(DoseFormat.qty(medication.dailyDoseTarget))/day remaining")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add to batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(selectedBatch == nil ||
                                  DoseAllocation.isOverTarget(
                                    allocated: DoseAllocation.allocated(medication) + quantity,
                                    target: medication.dailyDoseTarget))
                }
            }
            .alert("Cannot Add", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .onAppear {
                quantity = min(1.0, max(0.5, DoseAllocation.remaining(medication)))
            }
        }
    }

    private func add() {
        guard let batch = selectedBatch else { return }
        do {
            try MedicationService.addToBatch(medication, batch, quantity: quantity, in: context)
            dismiss()
        } catch DoseAllocationError.exceedsDailyTarget {
            errorMessage = "Total allocation across batches cannot exceed the daily dose target."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Moves an existing membership to another batch (quantity carried over), routing
/// through `MedicationService.moveToBatch`.
struct MoveBatchSheet: View {
    let item: RoutineItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var allBatches: [Routine]

    @State private var errorMessage: String?

    private var available: [Routine] {
        let present = Set((item.medication?.routineItems ?? []).compactMap { $0.routine?.persistentModelID })
        return allBatches.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            List {
                if available.isEmpty {
                    Text("No other batches to move to.").foregroundStyle(.secondary)
                } else {
                    ForEach(available) { batch in
                        Button {
                            move(to: batch)
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: batch.colorHex)).frame(width: 10, height: 10)
                                Text(batch.name.isEmpty ? "Routine" : batch.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Move to batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Cannot Move", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }

    private func move(to routine: Routine) {
        do {
            try MedicationService.moveToBatch(item, to: routine, in: context)
            dismiss()
        } catch MembershipError.alreadyInBatch {
            errorMessage = "This medication is already in that batch."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
