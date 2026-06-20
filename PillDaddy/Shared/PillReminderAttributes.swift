import Foundation

/// Escalation stage for an overdue batch, derived from how far through the grace
/// window the dose is. Pure + shared between the app and the widget extension.
enum ReminderTier: String, Codable, Hashable {
    case calm     // freshly due
    case overdue  // visibly late
    case urgent   // close to being marked missed

    static func forElapsed(_ elapsed: TimeInterval, grace: TimeInterval) -> ReminderTier {
        guard grace > 0 else { return .urgent }
        let fraction = elapsed / grace
        switch fraction {
        case ..<(1.0 / 3.0): return .calm
        case ..<(3.0 / 4.0): return .overdue
        default: return .urgent
        }
    }
}
