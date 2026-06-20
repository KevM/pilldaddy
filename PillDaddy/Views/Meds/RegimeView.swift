import SwiftUI
import SwiftData

/// Active regime grouped under color batches, with a trailing PRN section.
struct RegimeView: View {
    @Query(sort: [SortDescriptor(\Batch.sortOrder), SortDescriptor(\Batch.timeOfDay)])
    private var batches: [Batch]
    @Query(filter: #Predicate<Medication> { $0.isActive && $0.isPRN }, sort: \Medication.name)
    private var prnMeds: [Medication]

    @State private var editingBatch: Batch?

    var body: some View {
        List {
            ForEach(batches) { batch in
                Section {
                    let items = activeItems(batch)
                    if items.isEmpty {
                        Text("No active medications")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            NavigationLink {
                                if let med = item.medication {
                                    MedicationDetailView(medication: med)
                                }
                            } label: {
                                row(item)
                            }
                        }
                    }
                } header: {
                    header(batch)
                }
            }

            if !prnMeds.isEmpty {
                Section("As needed (PRN)") {
                    ForEach(prnMeds) { med in
                        NavigationLink {
                            MedicationDetailView(medication: med)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(med.name)
                                Text(med.strengthDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editingBatch) { BatchEditor(batch: $0) }
    }

    private func header(_ batch: Batch) -> some View {
        HStack {
            Circle().fill(Color(hex: batch.colorHex)).frame(width: 12, height: 12)
            Text(batch.name.isEmpty ? "Batch" : batch.name)
            Text(batch.timeOfDay, style: .time)
            Spacer()
            Button("Edit") { editingBatch = batch }.font(.caption)
        }
    }

    private func row(_ item: BatchItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.medication?.name ?? "—")
                Text(item.medication?.strengthDescription ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                if let med = item.medication { DoseAllocationBadge(medication: med) }
            }
            Spacer()
            Text("\(DoseFormat.qty(item.quantity)) \(item.medication?.form ?? "")")
                .foregroundStyle(.secondary)
        }
    }

    private func activeItems(_ batch: Batch) -> [BatchItem] {
        (batch.items ?? [])
            .filter { ($0.medication?.isActive ?? false) && !($0.medication?.isPRN ?? false) }
            .sorted { ($0.medication?.name ?? "") < ($1.medication?.name ?? "") }
    }
}

#if DEBUG
#Preview {
    NavigationStack { RegimeView() }
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
