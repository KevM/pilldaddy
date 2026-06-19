import SwiftUI
import SwiftData

/// Detail for one medication: memberships, a "why/history" preview, and the
/// guided action set. Trivial edits use the editor; meaningful changes are gated.
struct MedicationDetailView: View {
    @Bindable var medication: Medication
    @Environment(\.modelContext) private var context

    @State private var sheet: DetailSheet?

    enum DetailSheet: Identifiable {
        case edit, dose, instructions, swap, lifecycle
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Strength", value: medication.strength)
                LabeledContent("Form", value: medication.form)
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

            if !(medication.batchItems ?? []).isEmpty {
                Section("Taken in") {
                    ForEach(medication.batchItems ?? []) { item in
                        HStack {
                            Circle().fill(Color(hex: item.batch?.colorHex ?? "#8E8E93"))
                                .frame(width: 10, height: 10)
                            Text(item.batch?.name ?? "—")
                            Spacer()
                            Text("\(DoseFormat.qty(item.quantity)) \(medication.form)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Why / history") {
                let events = (medication.changeEvents ?? [])
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(5)
                if events.isEmpty {
                    Text("No history yet").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(events)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eventTitle(event)).font(.subheadline).bold()
                            if !event.reasoning.isEmpty {
                                Text(event.reasoning).font(.caption)
                            }
                            if !event.oldValue.isEmpty || !event.newValue.isEmpty {
                                Text("\(event.oldValue) → \(event.newValue)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Actions") {
                if medication.isActive {
                    Button("Edit details") { sheet = .edit }
                    Button("Change dose…") { sheet = .dose }
                    if !medication.isPRN && !(medication.batchItems ?? []).isEmpty {
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
            }
        }
    }

    private func eventTitle(_ event: MedicationChangeEvent) -> String {
        switch MedChangeType(rawValue: event.eventType) {
        case .added: return "Added"
        case .doseChanged: return "Dose changed"
        case .instructionsChanged: return "Instructions changed"
        case .swapped: return "Swapped"
        case .discontinued: return "Discontinued"
        case .reactivated: return "Reactivated"
        case .note, .none: return "Note"
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
