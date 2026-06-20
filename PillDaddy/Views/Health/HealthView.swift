import SwiftUI
import SwiftData

/// The Health tab: recent readings (unsynced rows flagged), a "+" chooser, and
/// delete with disclosure. HealthKit writes go through a single shared writer.
struct HealthView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \HealthMetric.recordedAt, order: .reverse) private var metrics: [HealthMetric]

    @State private var showPicker = false
    @State private var route: MetricCaptureRoute?
    @State private var pendingDelete: HealthMetric?

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
                            Image(systemName: "icloud.slash")
                                .font(.caption).foregroundStyle(.tertiary)
                                .accessibilityLabel("Not synced to Apple Health")
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { pendingDelete = metric } }
                }
            }
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .overlay {
                if metrics.isEmpty {
                    ContentUnavailableView("No readings yet", systemImage: "heart",
                                           description: Text("Tap + to record one."))
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            MetricPickerSheet { route = $0 }
        }
        .sheet(item: $route) { route in
            switch route {
            case .scalar(let kind): ScalarCaptureView(kind: kind, writer: writer)
            case .vitals: VitalsCaptureView(writer: writer)
            }
        }
        .sheet(item: $pendingDelete) { metric in
            DeleteMetricSheet(metric: metric) {
                HealthMetricService.delete(metric, in: context)
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
