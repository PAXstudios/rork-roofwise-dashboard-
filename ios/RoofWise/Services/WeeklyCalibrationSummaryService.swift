import Foundation
import UserNotifications

final class WeeklyCalibrationSummaryService {
    static let shared = WeeklyCalibrationSummaryService()

    private init() {}

    func schedule(profile: UserCorrectionProfile, liftPercent: Int) {
        guard profile.weeklyCorrectionCount > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "RoofWise AI calibration"
        content.body = "\(profile.weeklyCorrectionCount) photos reviewed this week. AI is now \(liftPercent)% more accurate on wear-and-tear damage."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 7 * 24 * 60 * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "roofwise.weeklyCalibrationSummary",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
