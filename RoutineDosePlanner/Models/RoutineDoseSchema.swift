import SwiftData

/// Single source of truth for the SwiftData schema, reused by the app container and tests.
enum RoutineDoseSchema {
    static let schema = Schema([
        Medication.self,
        Routine.self,
        RoutineItem.self,
        DoseLog.self,
        MedicationChangeEvent.self,
        HealthMetric.self,
    ])
}
