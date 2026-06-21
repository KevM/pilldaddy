import SwiftUI
import SwiftData

/// The Health tab: recent readings (unsynced rows flagged), a "+" chooser, and
/// delete with disclosure. HealthKit writes go through a single shared writer.
struct HealthView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthMetric.recordedAt, order: .reverse) private var metrics: [HealthMetric]

    @State private var showAdd = false
    @State private var showSyncStatus = false
    @State private var pendingDelete: HealthMetric?
    @State private var confirmedDeleteMetric: HealthMetric?

    private let writer: HealthKitWriting = LiveHealthKitWriter()

    var body: some View {
        NavigationStack {
            List {
                ForEach(metrics) { metric in
                    HStack {
                        Text(MetricRegistry.definition(for: metric.metricKind).displayName)
                        Spacer()
                        Text(valueText(metric)).foregroundStyle(.secondary)
                        if !metric.healthKitSynced {
                            Button {
                                showSyncStatus = true
                            } label: {
                                Image(systemName: "heart.slash")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Not in Apple Health — tap for options")
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { pendingDelete = metric } }
                }
            }
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if metrics.isEmpty {
                    ContentUnavailableView("No readings yet", systemImage: "heart",
                                           description: Text("Tap + to record one."))
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMetricFlow(writer: writer)
        }
        .sheet(item: $pendingDelete, onDismiss: {
            if let metric = confirmedDeleteMetric {
                HealthMetricService.delete(metric, in: context)
                confirmedDeleteMetric = nil
            }
        }) { metric in
            DeleteMetricSheet(metric: metric) {
                confirmedDeleteMetric = metric
            }
        }
        .sheet(isPresented: $showSyncStatus) {
            NavigationStack {
                HealthSyncStatusView(writer: writer)
            }
        }
    }

    private func valueText(_ m: HealthMetric) -> String {
        if m.metricKind == .bloodPressure, let d = m.secondaryValue {
            return MetricFormatter.bloodPressure(m.value, d) + " mmHg"
        }
        return MetricFormatter.string(m.value, unit: m.unit)
    }
}

#if DEBUG
#Preview {
    HealthView().modelContainer(PreviewSupport.seededContainer())
}
#endif
