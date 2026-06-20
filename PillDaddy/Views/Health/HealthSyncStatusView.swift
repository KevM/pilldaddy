import SwiftUI
import SwiftData
import UIKit

/// Reusable Apple Health authorization + sync disclosure. Pushed from Settings and
/// presented as a sheet from the Health tab's per-row indicator.
struct HealthSyncStatusView: View {
    let writer: HealthKitWriting

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var pending = 0
    @State private var syncMessage: String?
    @State private var isSyncing = false

    private var overall: HealthAuthState { HealthMetricService.overallAuthorization(writer: writer) }

    var body: some View {
        Form {
            Section { headerRow }

            if overall != .unavailable {
                Section("Metrics") {
                    ForEach(MetricKind.allCases) { kind in metricRow(kind) }
                }

                Section {
                    if pending > 0 {
                        Text("\(pending) reading\(pending == 1 ? "" : "s") waiting to sync to Apple Health")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await sync() }
                    } label: {
                        if isSyncing { ProgressView() } else { Text("Sync to Health") }
                    }
                    .disabled(pending == 0 || isSyncing)
                    if let syncMessage {
                        Text(syncMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Open iOS Settings") { openSettings() }
                }
            }
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { pending = HealthMetricService.pendingCount(in: context) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pending = HealthMetricService.pendingCount(in: context) }
        }
    }

    @ViewBuilder private var headerRow: some View {
        switch overall {
        case .authorized:
            Label("Full access", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .partial:
            Label("Partial access", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .denied:
            Label("Not enabled", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .notDetermined:
            Label("Not set up yet", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        case .unavailable:
            Label("Apple Health unavailable on this device", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func metricRow(_ kind: MetricKind) -> some View {
        let status = writer.authorizationStatus(for: kind)
        return HStack {
            Text(MetricRegistry.definition(for: kind).displayName)
            Spacer()
            Text(statusText(status)).font(.subheadline).foregroundStyle(statusColor(status))
        }
    }

    private func statusText(_ s: HealthShareAuthorization) -> String {
        switch s {
        case .authorized: "Sharing"
        case .denied: "Not shared"
        case .notDetermined: "Not set"
        }
    }

    private func statusColor(_ s: HealthShareAuthorization) -> Color {
        switch s {
        case .authorized: .green
        case .denied: .orange
        case .notDetermined: .secondary
        }
    }

    @MainActor private func sync() async {
        isSyncing = true
        let n = await HealthMetricService.resyncPending(writer: writer, in: context)
        pending = HealthMetricService.pendingCount(in: context)
        syncMessage = n > 0 ? "Synced \(n) reading\(n == 1 ? "" : "s")" : "Nothing to sync"
        isSyncing = false
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HealthSyncStatusView(writer: LiveHealthKitWriter())
            .modelContainer(PreviewSupport.seededContainer())
    }
}
#endif
