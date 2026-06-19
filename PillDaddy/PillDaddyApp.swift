import SwiftUI
import SwiftData

@main
struct PillDaddyApp: App {
    let container: ModelContainer

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
        }
        .modelContainer(container)
    }
}
