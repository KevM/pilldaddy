import Foundation
import Observation

/// Holds a pending deep-link navigation intent (a batch to focus on the Today tab).
/// Set by the notification delegate and the Live Activity widgetURL handler.
/// Not `@MainActor` so `AppDelegate` can default-initialize it as a stored property;
/// all mutations happen on the main thread.
@Observable
final class AppRouter {
    var pendingBatchUUID: String?
}
