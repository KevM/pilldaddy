import SwiftUI
import SwiftData

/// Regime-style "as-needed" card. The per-drug log UI is hidden until expanded.
struct PRNCard: View {
    let doses: [DayQuery.PRNDose]
    let day: Date
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.modelContext) private var context
    @State private var loggingMed: Medication?

    private var loggedCount: Int {
        doses.reduce(0) { $0 + $1.logs.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Text("As-needed").font(.headline)
                    Spacer()
                    Text("\(loggedCount)").foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(doses) { dose in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(dose.med.name)
                                Text(dose.med.strength).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Log a dose") { loggingMed = dose.med }
                                .font(.caption).buttonStyle(.borderedProminent)
                        }
                        ForEach(dose.logs) { log in
                            HStack {
                                Text("↳ \((log.takenAt ?? log.scheduledDate), style: .time) · \(DoseFormat.qty(log.quantity))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    DoseLogService.deletePRNLog(log, in: context)
                                } label: { Image(systemName: "trash").font(.caption) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .sheet(item: $loggingMed) { PRNLogSheet(medication: $0, day: day) }
    }
}

#if DEBUG
#Preview {
    let container = PreviewSupport.seededContainer()
    let meds = try! container.mainContext.fetch(
        FetchDescriptor<Medication>(predicate: #Predicate { $0.isActive && $0.isPRN }))
    return PRNCard(doses: DayQuery.prnDoses(from: meds, on: .now),
                   day: .now,
                   isExpanded: true, onToggle: {})
        .modelContainer(container)
        .padding()
}
#endif
