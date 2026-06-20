import SwiftData

/// Single source of truth for the SwiftData schema, reused by the app container and tests.
enum PillDaddySchema {
    static let schema = Schema([
        Medication.self,
        Batch.self,
        BatchItem.self,
        DoseLog.self,
        MedicationChangeEvent.self,
        HealthMetric.self,
    ])
}
