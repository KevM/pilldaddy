import SwiftUI
import SwiftData

/// The full, lineage-aware reasoning timeline for a medication: a single
/// reverse-chronological stream merging change events across the whole therapy
/// line (swap chain). Pushed from MedicationDetailView; add-note lives here.
struct MedicationTimelineView: View {
    let anchor: Medication
    @State private var showAddNote = false

    var body: some View {
        List {
            let events = MedicationLineage.events(from: anchor)
            if events.isEmpty {
                Text("No history yet").foregroundStyle(.secondary)
            } else {
                ForEach(events) { item in
                    TimelineEventRow(item: item)
                }
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddNote = true } label: {
                    Label("Add note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddNote) {
            AddNoteSheet(medication: anchor)
        }
    }
}

/// One row in a lineage timeline. Reused by MedicationDetailView's preview.
struct TimelineEventRow: View {
    let item: LineageEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(MedicationLineage.title(for: item)).font(.subheadline).bold()
                if let tag = attributionTag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(item.event.timestamp, format: .dateTime.month().day())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !item.event.reasoning.isEmpty {
                Text(item.event.reasoning).font(.caption)
            }
            if !item.event.oldValue.isEmpty || !item.event.newValue.isEmpty {
                Text("\(item.event.oldValue) → \(item.event.newValue)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Drug-name tag for non-anchor rows that aren't swaps (swap titles already
    /// name the destination; anchor rows are implicitly "this med").
    private var attributionTag: String? {
        guard !item.isAnchor,
              item.event.eventType != MedChangeType.swapped.rawValue else { return nil }
        return item.owningMed.name
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    return NavigationStack {
        MedicationTimelineView(anchor: PreviewSupport.firstMedication(container))
    }
    .modelContainer(container)
}
#endif
