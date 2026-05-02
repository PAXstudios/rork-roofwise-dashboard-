import Foundation
import UserNotifications
import UIKit

/// Routes auto-trip detection notifications back into the in-app log flow.
@MainActor
final class MileageNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MileageNotificationDelegate()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let tripId = info[MileageAutoTrackService.userInfoTripIdKey] as? String

        Task { @MainActor in
            guard let tripId else { completionHandler(); return }
            switch action {
            case MileageAutoTrackService.logActionId, UNNotificationDefaultActionIdentifier:
                AutoTripInbox.shared.presentIfNeeded(idString: tripId)
            case MileageAutoTrackService.dismissActionId:
                if let uuid = UUID(uuidString: tripId) {
                    AutoTripInbox.shared.remove(id: uuid)
                }
            default:
                break
            }
            completionHandler()
        }
    }
}
