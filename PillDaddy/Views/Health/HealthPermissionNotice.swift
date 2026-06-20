import SwiftUI
import UIKit

/// Compact inline notice shown on a capture screen when the metric being entered isn't
/// authorized to write to Apple Health. Renders nothing when authorized or unavailable.
/// Refreshes when the app returns to the foreground (e.g. after the user grants access).
struct HealthPermissionNotice: View {
    let kind: MetricKind
    let writer: HealthKitWriting

    @Environment(\.scenePhase) private var scenePhase
    @State private var status: HealthShareAuthorization = .authorized   // default avoids a flash
    @State private var showDetails = false

    var body: some View {
        Group {
            if writer.isHealthDataAvailable && status != .authorized {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(MetricRegistry.definition(for: kind).displayName) won't be saved to Apple Health",
                          systemImage: "heart.slash")
                        .font(.footnote).foregroundStyle(.orange)
                    HStack {
                        Button("Open Settings") { openSettings() }.font(.footnote)
                        Spacer()
                        Button("Details") { showDetails = true }.font(.footnote)
                    }
                }
            }
        }
        .onAppear { status = writer.authorizationStatus(for: kind) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { status = writer.authorizationStatus(for: kind) }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack { HealthSyncStatusView(writer: writer) }
        }
    }

    private func openSettings() {
        let newHealthURLString = "settings-navigation://com.apple.Settings.PrivacyAndSecurity/HEALTH"
        let healthURLString = "App-Prefs:root=Privacy&path=HEALTH"
        
        if let newUrl = URL(string: newHealthURLString) {
            UIApplication.shared.open(newUrl, options: [:]) { success in
                if !success {
                    if let oldUrl = URL(string: healthURLString) {
                        UIApplication.shared.open(oldUrl, options: [:]) { successOld in
                            if !successOld {
                                if let fallbackUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(fallbackUrl)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
