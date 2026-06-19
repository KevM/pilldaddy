import SwiftData
import XCTest
@testable import PillDaddy

enum ModelTestSupport {
    /// An in-memory ModelContainer (no CloudKit) holding the full PillDaddy schema.
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: PillDaddySchema.schema, configurations: config)
    }
}
