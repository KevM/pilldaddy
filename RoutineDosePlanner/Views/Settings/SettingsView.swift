import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct SettingsView: View {
    @Environment(ReminderSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    private let healthWriter: HealthKitWriting = LiveHealthKitWriter()

    private let graceChoices: [(String, Int)] = [
        ("30 min", 30), ("1 hour", 60), ("90 min", 90),
        ("2 hours", 120), ("3 hours", 180), ("4 hours", 240),
    ]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section(footer: Text("Schedules notifications and a Live Activity for each routine.")) {
                    Toggle("Reminders", isOn: $settings.remindersEnabled)
                }

                Section(header: Text("Timing"), footer: Text("How long after a routine's time before a dose is marked missed. "
                         + "Also how long reminders keep pestering.")) {
                    Toggle("15-minute heads-up", isOn: $settings.headsUpEnabled)
                    Picker("Grace window", selection: $settings.graceMinutes) {
                        ForEach(graceChoices, id: \.1) { Text($0.0).tag($0.1) }
                    }
                }

                Section(header: Text("Notifications")) {
                    permissionRow
                }

                Section(header: Text("Apple Health")) {
                    NavigationLink {
                        HealthSyncStatusView(writer: healthWriter)
                    } label: {
                        Label("Apple Health", systemImage: "heart")
                    }
                }

            }
            .navigationTitle("Settings")
            .onChange(of: settings.remindersEnabled) { _, _ in sync() }

            .onChange(of: settings.headsUpEnabled) { _, _ in sync() }
            .onChange(of: settings.graceMinutes) { _, _ in sync() }
            .task { await loadAuthStatus() }
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        switch authStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Notifications allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        default:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Notifications off — open Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func sync() {
        ReminderSync.refresh(context: context, settings: settings)
    }

    private func loadAuthStatus() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(ReminderSettings())
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
