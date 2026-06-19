import SwiftUI
import SwiftData

/// Flat A–Z list of medications with show/hide-discontinued and a guarded hard delete.
struct AllMedsView: View {
    @Query(sort: \Medication.name) private var allMeds: [Medication]
    @Environment(\.modelContext) private var context

    @State private var showDiscontinued = false
    @State private var pendingDelete: Medication?

    private var visibleMeds: [Medication] {
        showDiscontinued ? allMeds : allMeds.filter { $0.isActive }
    }

    var body: some View {
        List {
            Toggle("Show discontinued", isOn: $showDiscontinued)
            ForEach(visibleMeds) { med in
                NavigationLink {
                    MedicationDetailView(medication: med)
                } label: {
                    row(med)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = med }
                }
            }
        }
        .confirmationDialog(
            "Permanently delete this medication and its history? This can't be undone. To stop a med while keeping its history, use Discontinue instead.",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                if let med = pendingDelete {
                    context.delete(med)
                    try? context.save()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func row(_ med: Medication) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(med.name)
                Text(subtitle(med)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !med.isActive {
                tag("Discontinued")
            } else if med.isPRN {
                tag("PRN")
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.secondary.opacity(0.2))
            .clipShape(Capsule())
    }

    private func subtitle(_ med: Medication) -> String {
        let batches = (med.batchItems ?? []).compactMap { $0.batch?.name }.sorted()
        let suffix = batches.isEmpty ? "" : " · " + batches.joined(separator: ", ")
        return med.strength + suffix
    }
}

#if DEBUG
#Preview {
    NavigationStack { AllMedsView() }
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
