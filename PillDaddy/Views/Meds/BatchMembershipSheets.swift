import SwiftUI
import SwiftData

/// Adds the medication to a batch it is not already in, with an allocation-capped
/// quantity. Routes through `MedicationService.addToBatch`.
struct AddToBatchSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var allBatches: [Batch]

    @State private var selectedBatch: Batch?
    @State private var quantity = 1.0
    @State private var errorMessage: String?

    private var available: [Batch] {
        let present = Set((medication.batchItems ?? []).compactMap { $0.batch?.persistentModelID })
        return allBatches.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if available.isEmpty {
                    Text("This medication is already in every batch.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Batch", selection: $selectedBatch) {
                        Text("Select…").tag(Batch?.none)
                        ForEach(available) { batch in
                            Text(batch.name.isEmpty ? "Batch" : batch.name).tag(Batch?.some(batch))
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
    let item: BatchItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var allBatches: [Batch]

    @State private var errorMessage: String?

    private var available: [Batch] {
        let present = Set((item.medication?.batchItems ?? []).compactMap { $0.batch?.persistentModelID })
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
                                Text(batch.name.isEmpty ? "Batch" : batch.name)
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

    private func move(to batch: Batch) {
        do {
            try MedicationService.moveToBatch(item, to: batch, in: context)
            dismiss()
        } catch MembershipError.alreadyInBatch {
            errorMessage = "This medication is already in that batch."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
