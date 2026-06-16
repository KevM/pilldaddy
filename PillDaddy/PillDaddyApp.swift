import SwiftUI
import SwiftData

@main
struct PillDaddyApp: App {
    let container: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                Pill.self,
                PillColor.self,
                DoseLog.self,
                DoseChangeLog.self
            ])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            container = try ModelContainer(for: schema, configurations: config)
            
            // Seed default colors if needed
            seedDefaultColors()
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark) // Lock to dark theme for premium aesthetics
        }
        .modelContainer(container)
    }
    
    @MainActor
    private func seedDefaultColors() {
        let context = container.mainContext
        let fetchDescriptor = FetchDescriptor<PillColor>()
        do {
            let existingColors = try context.fetch(fetchDescriptor)
            if existingColors.isEmpty {
                let defaultColors = [
                    PillColor(name: "Morning Yellow", colorHex: "#F59E0B"),
                    PillColor(name: "Noon Teal", colorHex: "#14B8A6"),
                    PillColor(name: "Evening Blue", colorHex: "#3B82F6"),
                    PillColor(name: "Bedtime Purple", colorHex: "#8B5CF6"),
                    PillColor(name: "SOS Red", colorHex: "#EF4444"),
                    PillColor(name: "Supplement Green", colorHex: "#10B981")
                ]
                for color in defaultColors {
                    context.insert(color)
                }
                try context.save()
            }
        } catch {
            print("Failed to seed default colors: \(error.localizedDescription)")
        }
    }
}
