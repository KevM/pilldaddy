import Foundation

/// Relationship of a batch to a meal. Stored on Batch as a raw String.
enum MealRelation: String, CaseIterable, Identifiable {
    case none, withFood, beforeFood, afterFood
    var id: String { rawValue }
}

/// How often a batch recurs. Stored on Batch as a raw String.
enum RecurrenceKind: String, CaseIterable, Identifiable {
    case daily, weekdays
    var id: String { rawValue }
}

/// Outcome of a scheduled (or PRN) dose. Stored on DoseLog as a raw String.
enum DoseStatus: String, CaseIterable, Identifiable {
    case taken, skipped, missed
    var id: String { rawValue }
}

/// Type of medication lifecycle event. Stored on MedicationChangeEvent as a raw String.
enum MedChangeType: String, CaseIterable, Identifiable {
    case added, doseChanged, instructionsChanged, swapped, discontinued, reactivated, note
    var id: String { rawValue }
}

/// A health metric kind. Stored on HealthMetric as a raw String.
enum MetricKind: String, CaseIterable, Identifiable {
    case weight, water, bloodPressure, pulse, oxygenSaturation
    var id: String { rawValue }
}

