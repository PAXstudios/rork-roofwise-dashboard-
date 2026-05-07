import Foundation
import Observation

/// Routes notification taps into the in-app UI. The dashboard observes
/// `pendingAlertId` and presents a detail sheet whenever it becomes non-nil,
/// then clears it.
@Observable
@MainActor
final class PushAlertRouter {
    static let shared = PushAlertRouter()

    /// The id of a StormAlert that the user just tapped from a push.
    var pendingAlertId: UUID?

    private init() {}

    func present(alertId: UUID) {
        pendingAlertId = alertId
    }

    func clear() {
        pendingAlertId = nil
    }
}
