import SwiftUI
import SwiftData

/// Per-med taken / skip / clear for one batch on a day. A note is required when
/// any med is set to Skip (the note applies to those skips).
struct IndividualAdjustSheet: View {
    let batchDay: DayQuery.BatchDay
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum Choice: String, CaseIterable, Identifiable {
        case clear = "—", taken = "Taken", skip = "Skip"
        var id: String { rawValue }
    }

    @State private var choices: [PersistentIdentifier: Choice] = [:]
    @State private var note = ""

    private var anySkip: Bool { choices.values.contains(.skip) }
    private var saveDisabled: Bool {
        anySkip && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(batchDay.meds) { dose in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dose.item.medication?.name ?? "—")
                            Picker("", selection: binding(for: dose)) {
                                ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 2)
                    }
                }
                if anySkip {
                    Section("Reason for skip (required)") {
                        TextField("e.g. BP too low", text: $note, axis: .vertical)
                    }
                }
            }
            .navigationTitle("Adjust \(batchDay.batch.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saveDisabled)
                }
            }
            .onAppear(perform: seedChoices)
        }
    }

    private func binding(for dose: DayQuery.MedDose) -> Binding<Choice> {
        Binding(
            get: { choices[dose.id] ?? .clear },
            set: { choices[dose.id] = $0 })
    }

    private func seedChoices() {
        for dose in batchDay.meds {
            switch dose.log?.status {
            case DoseStatus.taken.rawValue: choices[dose.id] = .taken
            case DoseStatus.skipped.rawValue: choices[dose.id] = .skip
            default: choices[dose.id] = .clear
            }
        }
    }

    private func save() {
        for dose in batchDay.meds {
            switch choices[dose.id] ?? .clear {
            case .taken:
                try? DoseLogService.logMed(dose.item, on: day, status: .taken,
                                           takenAt: .now, note: "", in: context)
            case .skip:
                try? DoseLogService.logMed(dose.item, on: day, status: .skipped,
                                           takenAt: nil, note: note, in: context)
            case .clear:
                DoseLogService.revert(dose.item, on: day, in: context)
            }
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let batches = try! container.mainContext.fetch(
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.sortOrder)]))
    let day = DayQuery.batchDays(from: batches, on: .now).first!
    return IndividualAdjustSheet(batchDay: day, day: .now)
        .modelContainer(container)
}
#endif
