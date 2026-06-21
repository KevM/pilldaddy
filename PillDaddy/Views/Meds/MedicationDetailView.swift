import SwiftUI
import SwiftData

/// Detail for one medication: memberships, a "why/history" preview, and the
/// guided action set. Trivial edits use the editor; meaningful changes are gated.
struct MedicationDetailView: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context

    @State private var sheet: DetailSheet?
    @State private var movingItem: RoutineItem?
    @State private var errorMessage: String?

    enum DetailSheet: Identifiable {
        case edit, dose, instructions, swap, lifecycle, addToBatch
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Strength", value: medication.strengthDescription)
                LabeledContent("Form", value: medication.form)
                DoseAllocationBadge(medication: medication, showCaption: true)
                if medication.isPRN {
                    Text("As needed (PRN)").foregroundStyle(.secondary)
                }
                if !medication.isActive {
                    Text("Discontinued").foregroundStyle(.secondary)
                }
                if !medication.generalNotes.isEmpty {
                    Text(medication.generalNotes).font(.callout)
                }
            }

            if medication.isActive && !medication.isPRN {
                Section("Schedule") {
                    ForEach(medication.routineItems ?? []) { item in
                        Menu {
                            Button("Move to another batch…") { movingItem = item }
                            Button("Remove from batch", role: .destructive) {
                                do {
                                    try MedicationService.removeFromBatch(item, in: context)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: item.routine?.colorHex ?? "#8E8E93"))
                                    .frame(width: 10, height: 10)
                                Text(item.routine?.name ?? "—")
                                Spacer()
                                Text("\(DoseFormat.qty(item.quantity)) \(medication.form)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Add to batch…") { sheet = .addToBatch }
                        .disabled(DoseAllocation.remaining(medication) <= 0)
                }
            }

            Section("Why / history") {
                let events = MedicationLineage.events(from: medication)
                if events.isEmpty {
                    Text("No history yet").foregroundStyle(.secondary)
                } else {
                    ForEach(events.prefix(5)) { item in
                        TimelineEventRow(item: item)
                    }
                }
                NavigationLink("Full history & notes") {
                    MedicationTimelineView(anchor: medication)
                }
            }

            Section("Actions") {
                if medication.isActive {
                    Button("Edit details") { sheet = .edit }
                    Button("Change dose…") { sheet = .dose }
                    if !medication.isPRN && !(medication.routineItems ?? []).isEmpty {
                        Button("Change instructions…") { sheet = .instructions }
                    }
                    Button("Swap to another drug…") { sheet = .swap }
                    Button("Discontinue…", role: .destructive) { sheet = .lifecycle }
                } else {
                    Button("Reactivate…") { sheet = .lifecycle }
                    Button("Edit details") { sheet = .edit }
                }
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case .edit: MedicationEditor(mode: .edit(medication))
            case .dose: ChangeDoseSheet(medication: medication)
            case .instructions: ChangeInstructionsSheet(medication: medication)
            case .swap: SwapSheet(oldMed: medication)
            case .lifecycle: LifecycleReasonSheet(medication: medication, reactivating: !medication.isActive)
            case .addToBatch: AddToBatchSheet(medication: medication)
            }
        }
        .sheet(item: $movingItem) { item in
            MoveBatchSheet(item: item)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return NavigationStack {
        MedicationDetailView(medication: PreviewSupport.firstMedication(container))
    }
    .modelContainer(container)
}
#endif
