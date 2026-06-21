import SwiftUI
import SwiftData

/// One batch on the Today screen. Collapsed → summary; expanded → meds + actions.
struct BatchLogCard: View {
    let batchDay: DayQuery.BatchDay
    let isExpanded: Bool
    let onToggle: () -> Void
    let onMarkAllTaken: () -> Void
    let onAdjust: () -> Void
    let onRevert: () -> Void

    private var color: Color { Color(hex: batchDay.batch.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack {
                    Circle().fill(color).frame(width: 12, height: 12)
                    VStack(alignment: .leading) {
                        Text(batchDay.batch.name.isEmpty ? "Batch" : batchDay.batch.name)
                            .font(.headline)
                        Text(batchDay.slotDate, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusChip
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(batchDay.meds) { dose in
                    HStack {
                        Text(dose.item.medication?.name ?? "—")
                        Spacer()
                        Text("\(DoseFormat.qty(dose.item.quantity)) \(dose.item.medication?.form ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        medChip(dose)
                    }
                }
                actionButtons
            }
        }
        .padding()
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var statusChip: some View {
        Group {
            switch batchDay.state {
            case .taken: Label("Taken", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .skipped: Label("Skipped", systemImage: "xmark.circle.fill").foregroundStyle(.orange)
            case .missed: Label("Missed", systemImage: "exclamationmark.circle.fill").foregroundStyle(.secondary)
            case .completed: Label("Completed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            case .partial: Text("Partial").foregroundStyle(.orange)
            case .pending: Text("Pending").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    @ViewBuilder private func medChip(_ dose: DayQuery.MedDose) -> some View {
        switch dose.log?.status {
        case DoseStatus.taken.rawValue:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case DoseStatus.skipped.rawValue:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange).font(.caption)
        case DoseStatus.missed.rawValue:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption)
        default:
            Image(systemName: "circle").foregroundStyle(.secondary).font(.caption)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        VStack(spacing: 8) {
            if !batchDay.isCompleted {
                Button("Mark all taken", action: onMarkAllTaken)
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
            Button("Adjust individually…", action: onAdjust)
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            if batchDay.state != .pending {
                Button("Clear log", role: .destructive, action: onRevert)
                    .font(.caption)
            }
        }
        .padding(.top, 4)
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let batches = try! container.mainContext.fetch(
        FetchDescriptor<Batch>(sortBy: [SortDescriptor(\.timeOfDay), SortDescriptor(\.uuid)]))
    let day = DayQuery.batchDays(from: batches, on: .now).first!
    return BatchLogCard(batchDay: day, isExpanded: true, onToggle: {},
                        onMarkAllTaken: {}, onAdjust: {}, onRevert: {})
        .modelContainer(container)
        .padding()
}
#endif
