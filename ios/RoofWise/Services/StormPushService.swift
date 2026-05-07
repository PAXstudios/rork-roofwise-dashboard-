import Foundation
import Observation
import UserNotifications

/// Local push notifications for storm alerts.
///
/// Owns:
///   - Permission request + cached `authorizationStatus`
///   - Notification category registration (View / Snooze 1h / Dismiss actions)
///   - Scheduling a local notification for each newly-ingested StormAlert
///   - User-facing prefs (master toggle, sound, snooze duration) persisted via
///     UserDefaults.
///
/// Routing of taps lives in `MileageNotificationDelegate` which now handles
/// both mileage and storm categories.
@Observable
@MainActor
final class StormPushService {
    static let shared = StormPushService()

    // MARK: Notification identifiers
    static let categoryId = "rw.storm.alert"
    static let viewActionId = "rw.storm.alert.view"
    static let snoozeActionId = "rw.storm.alert.snooze"
    static let dismissActionId = "rw.storm.alert.dismiss"
    static let userInfoAlertIdKey = "stormAlertId"

    // MARK: User prefs (UserDefaults-backed)
    private let enabledKey = "rw.storm.push.enabled"
    private let soundKey = "rw.storm.push.sound"
    private let snoozeMinutesKey = "rw.storm.push.snoozeMinutes"

    var isEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var soundEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: soundKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    /// Snooze duration applied when the user taps the "Snooze" notification action.
    var snoozeMinutes: Int {
        get { (UserDefaults.standard.object(forKey: snoozeMinutesKey) as? Int) ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: snoozeMinutesKey) }
    }

    // MARK: Permission state
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {}

    // MARK: Public API

    /// Register the storm notification category alongside any other categories
    /// already registered (e.g. mileage). Safe to call multiple times.
    func registerCategory() {
        let view = UNNotificationAction(
            identifier: Self.viewActionId,
            title: "View",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionId,
            title: "Snooze 1h",
            options: []
        )
        let dismiss = UNNotificationAction(
            identifier: Self.dismissActionId,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [view, snooze, dismiss],
            intentIdentifiers: [],
            options: []
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var merged = existing
            merged.insert(category)
            center.setNotificationCategories(merged)
        }
    }

    /// Refresh `authorizationStatus` from UNUserNotificationCenter.
    func refreshStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = s.authorizationStatus
    }

    /// Prompt for notification permission. No-ops if already determined.
    @discardableResult
    func requestAuthorization() async -> Bool {
        registerCategory()
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }

    /// Schedule a local notification for a freshly-ingested StormAlert.
    /// No-op if the user disabled storm pushes or hasn't authorized.
    func notify(for alert: StormAlert) {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [soundEnabled] settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "RoofWise · Storm Alert"
            content.body = Self.bodyText(for: alert)
            if soundEnabled { content.sound = .default }
            content.categoryIdentifier = Self.categoryId
            content.userInfo = [Self.userInfoAlertIdKey: alert.id.uuidString]
            content.threadIdentifier = "rw.storm.\(alert.areaId.uuidString)"

            let req = UNNotificationRequest(
                identifier: "rw.storm.\(alert.id.uuidString)",
                content: content,
                trigger: nil
            )
            center.add(req, withCompletionHandler: nil)
        }
    }

    /// Compose the human notification body for an alert.
    nonisolated static func bodyText(for alert: StormAlert) -> String {
        let mag: String
        switch alert.eventType {
        case .hail:
            if let m = alert.magnitudeIn { mag = String(format: "%.2f″ hail", m) }
            else { mag = "Hail" }
        case .wind:
            if let m = alert.windMph { mag = "\(m) mph wind" }
            else { mag = "High wind" }
        case .tornado:
            mag = "Tornado"
        }
        let where_ = alert.areaLabel
        let n = alert.propertyCount
        let propText = n == 1 ? "1 property nearby" : "\(n) properties nearby"
        return "\(mag) near \(where_) — \(propText). Tap to view."
    }
}
