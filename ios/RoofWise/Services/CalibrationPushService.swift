import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
import UserNotifications

/// Phase 9F. Weekly summary push that surfaces calibration progress.
/// Sibling BGAppRefreshTask to `StormWatchService`. Skips silently when push
/// permission is denied. Reads from `CorrectionsStore` + `LocalLearningEngine`.
@MainActor
final class CalibrationPushService {
    static let shared = CalibrationPushService()

    static let bgTaskIdentifier = "com.roofwise.calibration_weekly"
    private static let lastSentKey = "rw.calibration.weekly.lastSentAt"

    private init() {}

    nonisolated static func registerBackgroundTasks() {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                CalibrationPushService.shared.scheduleNext()
                await CalibrationPushService.shared.runIfDue()
                refresh.setTaskCompleted(success: true)
            }
        }
        #endif
    }

    func scheduleNext() {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        let req = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(req)
        #endif
    }

    func runIfDue() async {
        let now = Date()
        let last = (UserDefaults.standard.object(forKey: Self.lastSentKey) as? Date) ?? .distantPast
        guard now.timeIntervalSince(last) >= 7 * 86_400 else { return }

        let weekly = CorrectionsStore.shared.recent(days: 7)
        guard !weekly.isEmpty else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        // Find category that improved most this week.
        var perCatCount: [String: Int] = [:]
        for c in weekly {
            for cat in c.categoriesAffected {
                perCatCount[cat, default: 0] += 1
            }
        }
        let topCategory = perCatCount.max(by: { $0.value < $1.value })?.key ?? "damage"
        let pretty = topCategory.replacingOccurrences(of: "_", with: " ")
        let accuracy = LocalLearningEngine.shared.profile.perCategoryAccuracy[topCategory] ?? 0
        let pct = Int((accuracy * 100).rounded())

        let body = "\(weekly.count) photos reviewed this week. AI is now \(pct)% more accurate on \(pretty)."
        let content = UNMutableNotificationContent()
        content.title = "RoofWise AI"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "rw.calibration.weekly.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(now, forKey: Self.lastSentKey)
    }
}
