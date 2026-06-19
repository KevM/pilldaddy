#if DEBUG
import SwiftData

/// A seeded in-memory container for SwiftUI previews.
@MainActor
enum PreviewSupport {
    static func seededContainer() -> ModelContainer {
        let container = try! ModelContainer(
            for: PillDaddySchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        SeedData.seedIfEmpty(container.mainContext)
        try? container.mainContext.save()
        return container
    }

    /// First medication in the seeded store (for detail/editor previews).
    static func firstMedication(_ container: ModelContainer) -> Medication {
        try! container.mainContext.fetch(FetchDescriptor<Medication>()).first!
    }
}
#endif
