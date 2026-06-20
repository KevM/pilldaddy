import SwiftUI
import UIKit

/// Custom delete confirmation. For Apple-Health-synced rows it discloses that the
/// reading stays in Health, with an (i) expander, an Open Health action, and the
/// metric's breadcrumb. (A system alert can't host the disclosure.)
struct DeleteMetricSheet: View {
    let metric: HealthMetric
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showWhy = false

    private var def: MetricDefinition { MetricRegistry.definition(for: metric.metricKind) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "trash").font(.largeTitle).foregroundStyle(.red)
                Text("Delete this reading?").font(.headline)
                Text(def.displayName).foregroundStyle(.secondary)

                if metric.healthKitSynced {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "heart.text.square")
                            Text("It will stay in Apple Health").font(.subheadline)
                            Spacer()
                            Button { showWhy.toggle() } label: { Image(systemName: "info.circle") }
                        }
                        if showWhy {
                            Text("PillDaddy can add readings to Apple Health but can't remove them. "
                                 + "To delete it there: \(def.healthAppBreadcrumb).")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Open Health") { openHealth() }.font(.caption)
                        }
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Delete", role: .destructive) { dismiss(); onDelete() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .presentationDetents([.medium])
    }

    private func openHealth() {
        guard let url = URL(string: "x-apple-health://"),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
