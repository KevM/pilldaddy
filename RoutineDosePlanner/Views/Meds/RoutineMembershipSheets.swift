import SwiftUI
import SwiftData

/// Adds the medication to a routine it is not already in, with an allocation-capped
/// quantity. Routes through `MedicationService.addToRoutine`.
struct AddToRoutineSheet: View {
    let medication: Medication

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var allRoutines: [Routine]

    @State private var selectedRoutineID: PersistentIdentifier?
    @State private var quantity = 1.0
    @State private var errorMessage: String?

    private var selectedRoutine: Routine? {
        guard let selectedRoutineID else { return nil }
        return available.first { $0.persistentModelID == selectedRoutineID }
    }

    private var available: [Routine] {
        let present = Set((medication.routineItems ?? []).compactMap { $0.routine?.persistentModelID })
        return allRoutines.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if available.isEmpty {
                    Text("This medication is already in every routine.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Routine", selection: $selectedRoutineID) {
                        Text("Select…").tag(PersistentIdentifier?.none)
                        ForEach(available) { routine in
                            Text(routine.name.isEmpty ? "Routine" : routine.name)
                                .tag(PersistentIdentifier?.some(routine.persistentModelID))
                        }
                    }
                    DoseQuantityField(
                        title: "Quantity", value: $quantity,
                        range: 0.5...20, step: 0.5,
                        max: selectedRoutine.map { DoseAllocation.remaining(medication, addingTo: $0) })
                    if let routine = selectedRoutine, let days = RecurrenceLabel.short(for: routine) {
                        Text("\(DoseFormat.qty(DoseAllocation.remaining(medication, addingTo: routine))) remaining on \(days)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let routine = selectedRoutine {
                        Text("\(DoseFormat.qty(DoseAllocation.remaining(medication, addingTo: routine))) remaining per day")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add to routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(selectedRoutine == nil ||
                                  selectedRoutine.map {
                                      DoseAllocation.adding(quantity, to: $0, exceedsTargetFor: medication)
                                  } ?? true)
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
                quantity = 1.0
            }
        }
    }

    private func add() {
        guard let routine = selectedRoutine else { return }
        do {
            try MedicationService.addToRoutine(medication, routine, quantity: quantity, in: context)
            dismiss()
        } catch DoseAllocationError.exceedsDailyTarget {
            errorMessage = "Total allocation across routines cannot exceed the daily dose target."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Moves an existing membership to another routine (quantity carried over), routing
/// through `MedicationService.moveToRoutine`.
struct MoveRoutineSheet: View {
    let item: RoutineItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Routine.timeOfDay), SortDescriptor(\Routine.uuid)])
    private var allRoutines: [Routine]

    @State private var errorMessage: String?

    private var available: [Routine] {
        let present = Set((item.medication?.routineItems ?? []).compactMap { $0.routine?.persistentModelID })
        return allRoutines.filter { !present.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            List {
                if available.isEmpty {
                    Text("No other routines to move to.").foregroundStyle(.secondary)
                } else {
                    ForEach(available) { routine in
                        Button {
                            move(to: routine)
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: routine.colorHex)).frame(width: 10, height: 10)
                                Text(routine.name.isEmpty ? "Routine" : routine.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Move to routine")
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
            try MedicationService.moveToRoutine(item, to: routine, in: context)
            dismiss()
        } catch MembershipError.alreadyInRoutine {
            errorMessage = "This medication is already in that routine."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
