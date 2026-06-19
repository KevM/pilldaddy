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
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(container)
    }
}
