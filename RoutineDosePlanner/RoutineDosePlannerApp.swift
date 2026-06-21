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

    // Tap → focus the routine on the Today tab.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let uuid = response.notification.request.content.userInfo["routineUUID"] as? String {
            await MainActor.run { router.pendingRoutineUUID = uuid }
        }
    }
}

@main
struct RoutineDosePlannerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let container: ModelContainer
    private let settings = ReminderSettings()
    private let healthWriter: HealthKitWriting = LiveHealthKitWriter()

    init() {
        do {
            let config = ModelConfiguration(
                schema: RoutineDoseSchema.schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: RoutineDoseSchema.schema, configurations: config)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        DoseLogMigration.backfillPRNFlag(in: container.mainContext)

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
                    if url.scheme == "routine", url.host == "routine" {
                        appDelegate.router.pendingRoutineUUID = url.lastPathComponent
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard NSClassFromString("XCTestCase") == nil else { return }
                    if phase == .active {
                        syncReminders()
                        Task {
                            await HealthMetricService.resyncPending(writer: healthWriter, in: container.mainContext)
                        }
                    }
                }
        }
        .modelContainer(container)
    }

    @MainActor
    private func syncReminders() {
        let context = container.mainContext
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        MissedReconciler.reconcile(
            routines: routines, now: .now, graceMinutes: settings.graceMinutes, in: context)
        ReminderSync.refresh(context: context, settings: settings)
    }
}

