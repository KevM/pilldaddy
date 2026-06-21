import SwiftData
import XCTest
@testable import RoutineDosePlanner

enum ModelTestSupport {
    /// An in-memory ModelContainer (no CloudKit) holding the full RoutineDosePlanner schema.
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: RoutineSchema.schema, configurations: config)
    }
}
