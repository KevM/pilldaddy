import SwiftUI
import SwiftData

/// "Mark all taken" as a fill, not an overwrite. Un-logged meds → taken; already
/// taken → preserved; skipped → preserved unless the caregiver flips them here.
struct BatchTakenConfirmSheet: View {
    let batchDay: DayQuery.BatchDay
    let day: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var takenAt = Date.now
    @State private var note = ""
    /// Skipped meds the caregiver chose to flip to taken (by item id).
    @State private var flipped: Set<PersistentIdentifier> = []

    private var unlogged: [DayQuery.MedDose] { batchDay.meds.filter { $0.log == nil } }
    private var alreadyTaken: [DayQuery.MedDose] {
        batchDay.meds.filter { $0.log?.status == DoseStatus.taken.rawValue }
    }
    private var skipped: [DayQuery.MedDose] {
        batchDay.meds.filter { $0.log?.status == DoseStatus.skipped.rawValue }
    }
    private var missed: [DayQuery.MedDose] {
        batchDay.meds.filter { $0.log?.status == DoseStatus.missed.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") { DatePicker("Taken at", selection: $takenAt, displayedComponents: [.hourAndMinute]) }

                if !unlogged.isEmpty {
                    Section("Will be marked taken") {
                        ForEach(unlogged) { medRow($0) }
                    }
                }
                if !alreadyTaken.isEmpty {
                    Section("Already taken") {
                        ForEach(alreadyTaken) { dose in
                            medRow(dose).foregroundStyle(.secondary)
                        }
                    }
                }
                if !skipped.isEmpty {
                    Section("Skipped — tap to take instead") {
                        ForEach(skipped) { dose in
                            Button { toggleFlip(dose) } label: {
                                HStack {
                                    Image(systemName: flipped.contains(dose.id)
                                          ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(dose.item.medication?.name ?? "—")
                                        if let n = dose.log?.notes, !n.isEmpty {
                                            Text(n).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !missed.isEmpty {
                    Section("Missed — tap to take instead") {
                        ForEach(missed) { dose in
                            Button { toggleFlip(dose) } label: {
                                HStack {
                                    Image(systemName: flipped.contains(dose.id)
                                          ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(dose.item.medication?.name ?? "—")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("Applies to the doses being taken", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(batchDay.batch.name.isEmpty ? "Batch" : batchDay.batch.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                }
            }
            .onAppear {
                takenAt = DayQuery.combine(date: day, time: Date.now)
            }
        }
    }

    private func medRow(_ dose: DayQuery.MedDose) -> some View {
        HStack {
            Text(dose.item.medication?.name ?? "—")
            Spacer()
            Text("\(DoseFormat.qty(dose.item.quantity)) \(dose.item.medication?.form ?? "")")
                .foregroundStyle(.secondary)
        }
    }

    private func toggleFlip(_ dose: DayQuery.MedDose) {
        if flipped.contains(dose.id) { flipped.remove(dose.id) } else { flipped.insert(dose.id) }
    }

    private func confirm() {
        let fill = unlogged.map(\.item) + skipped.filter { flipped.contains($0.id) }.map(\.item) + missed.filter { flipped.contains($0.id) }.map(\.item)
        DoseLogService.logBatchTaken(batchDay.batch, on: day, items: fill,
                                     takenAt: takenAt, note: note, in: context)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let batches = try! container.mainContext.fetch(
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.sortOrder)]))
    let day = DayQuery.batchDays(from: batches, on: .now).first!
    return BatchTakenConfirmSheet(batchDay: day, day: .now)
        .modelContainer(container)
}
#endif
