import SwiftUI
import SwiftData
import UserNotifications
import UIKit

/// Owns the notification delegate and the deep-link router (kept alive for the app's life).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let router = AppRouter()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    // Show banners while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Tap → focus the batch on the Today tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let uuid = response.notification.request.content.userInfo["batchUUID"] as? String {
            await MainActor.run { router.pendingBatchUUID = uuid }
        }
    }
}

@main
struct PillDaddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer
    private let settings = ReminderSettings()

    init() {
        do {
            let config = ModelConfiguration(
                schema: PillDaddySchema.schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: PillDaddySchema.schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedTestData") {
            SeedData.seedIfEmpty(container.mainContext)
            try? container.mainContext.save()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appDelegate.router)
                .environment(settings)
                .onOpenURL { url in
                    if url.scheme == "pilldaddy", url.host == "batch" {
                        appDelegate.router.pendingBatchUUID = url.lastPathComponent
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { syncReminders() }
                }
        }
        .modelContainer(container)
    }

    @MainActor
    private func syncReminders() {
        let context = container.mainContext
        let batches = (try? context.fetch(FetchDescriptor<Batch>())) ?? []
        MissedReconciler.reconcile(
            batches: batches, now: .now, graceMinutes: settings.graceMinutes, in: context)
        ReminderSync.refresh(context: context, settings: settings)
    }
}

