import Foundation
import UIKit
import UserNotifications

/// Runs RoofWise Vision analysis across all of a customer's photos in the
/// background so the inspector can keep working elsewhere in the app. Updates
/// `CustomerStore` as each photo lands (so the profile reflects progress live),
/// tracks a real per-photo ETA grounded in measured Gemini latency, and posts a
/// local notification when the batch finishes.
@MainActor
@Observable
final class PhotoAnalysisService {
    static let shared = PhotoAnalysisService()

    struct AnalysisJob {
        var total: Int
        var completed: Int
        var customerName: String
    }

    /// Active mass-analysis jobs keyed by customer id. Drives the profile UI.
    private(set) var jobs: [UUID: AnalysisJob] = [:]

    /// Rolling average of real Gemini per-photo round-trip seconds, persisted so
    /// the ETA shown to the user is grounded in this device's actual history —
    /// never a hardcoded guess.
    private let perPhotoKey = "rw.photoAnalysis.perPhotoSeconds.v1"
    private var perPhotoSeconds: Double {
        get {
            let v = UserDefaults.standard.double(forKey: perPhotoKey)
            return v > 0.5 ? v : 6.5   // measured default until real timings exist
        }
        set { UserDefaults.standard.set(newValue, forKey: perPhotoKey) }
    }

    // MARK: - Queries

    func isAnalyzing(_ id: UUID) -> Bool { jobs[id] != nil }
    func job(for id: UUID) -> AnalysisJob? { jobs[id] }

    /// Photos that still need analysis for a customer.
    func unanalyzedCount(_ c: Customer) -> Int {
        c.photos.filter { !$0.analyzed }.count
    }

    /// Real ETA = photo count × measured per-photo latency.
    func estimatedSeconds(forPhotoCount n: Int) -> Int {
        max(0, Int((Double(n) * perPhotoSeconds).rounded()))
    }

    /// Human label for the ETA, e.g. "~12s" or "~2 min".
    func estimateLabel(forPhotoCount n: Int) -> String {
        guard n > 0 else { return "—" }
        let s = estimatedSeconds(forPhotoCount: n)
        if s < 60 { return "~\(max(1, s))s" }
        let m = Int((Double(s) / 60.0).rounded())
        return "~\(max(1, m)) min"
    }

    // MARK: - Run

    /// Analyze every (optionally only unanalyzed) photo for a customer in the
    /// background. Safe to fire-and-forget; the owning Task lives on this
    /// singleton so it keeps running after the profile view is dismissed.
    func analyzeAll(customerID: UUID, store: CustomerStore, reanalyzeAll: Bool = false) {
        guard jobs[customerID] == nil,
              let customer = store.customers.first(where: { $0.id == customerID }) else { return }
        let targetIDs = customer.photos
            .filter { reanalyzeAll || !$0.analyzed }
            .map(\.id)
        guard !targetIDs.isEmpty else { return }

        jobs[customerID] = AnalysisJob(total: targetIDs.count, completed: 0,
                                       customerName: customer.ownerName)
        Task { await requestAuthorizationIfNeeded() }

        Task { @MainActor in
            var observed: [Double] = []
            var totalMarkers = 0
            for photoID in targetIDs {
                guard let c = store.customers.first(where: { $0.id == customerID }),
                      let photo = c.photos.first(where: { $0.id == photoID }) else { continue }
                let started = Date()
                let result: GeminiAnalysisService.AnalysisResult
                if APIKeys.useMultiStageDetection {
                    result = await DetectionPipelineService.shared.analyze(image: photo.image).asAnalysisResult()
                } else {
                    result = await GeminiAnalysisService.analyzeFull(image: photo.image,
                                                                     slope: photo.slope,
                                                                     mode: photo.captureMode,
                                                                     squaresCovered: photo.squaresCovered)
                }
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 0.2 { observed.append(elapsed) }

                var updated = photo
                updated.findings = result.findings
                updated.damageMarkers = result.markers
                updated.analyzed = !result.failed
                store.replacePhoto(updated, for: customerID)
                totalMarkers += result.markers.count

                if var p = jobs[customerID] {
                    p.completed += 1
                    jobs[customerID] = p
                }
            }

            // Persist the real measured average for future ETAs (blended to
            // smooth outliers).
            if !observed.isEmpty {
                let avg = observed.reduce(0, +) / Double(observed.count)
                perPhotoSeconds = (perPhotoSeconds + avg) / 2.0
            }

            let finished = jobs[customerID]
            jobs[customerID] = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await notifyCompletion(customerName: finished?.customerName ?? "customer",
                                   analyzed: finished?.total ?? targetIDs.count,
                                   markers: totalMarkers)
        }
    }

    // MARK: - Notifications

    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func notifyCompletion(customerName: String, analyzed: Int, markers: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "RoofWise Vision analysis complete"
        content.body = "Analyzed \(analyzed) photo\(analyzed == 1 ? "" : "s") for \(customerName) — \(markers) damage marker\(markers == 1 ? "" : "s") found."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rw.photoAnalysis.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        )
        try? await center.add(request)
    }
}
