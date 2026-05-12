import Foundation
import Observation

/// Rolling stats over the user's most recent corrections. Powers the
/// `LocalLearningEngine` per-category threshold adjustments and the
/// "Calibrating to your inspection style" UI.
@Observable
final class UserCorrectionProfile {
    /// `correct / total` ratio per category (0.0-1.0).
    var perCategoryAccuracy: [String: Double] = [:]
    /// Count of `added_missed` corrections by category.
    var perCategoryUnderCount: [String: Int] = [:]
    /// Count of `removed_false_positive` corrections by category.
    var perCategoryOverCount: [String: Int] = [:]
    /// Derived calibration offset. Negative → user tends to add markers the AI
    /// misses (lower the threshold so we surface more). Positive → user tends
    /// to remove false positives (raise the threshold).
    var confidenceCalibrationOffset: Double = 0.0
    /// Per-category effective threshold (0-100). Base is 60; offsets are
    /// applied per category via `LocalLearningEngine.effectiveThreshold`.
    var perCategoryThreshold: [String: Double] = [:]
    /// Total corrections recorded ever.
    var totalCorrections: Int = 0
    /// Last recompute timestamp.
    var lastRecomputeAt: Date?

    init() {
        load()
    }

    // MARK: Persistence (UserDefaults JSON blob)

    private let storageKey = "rw.userCorrectionProfile.v1"

    private struct Snapshot: Codable {
        var perCategoryAccuracy: [String: Double]
        var perCategoryUnderCount: [String: Int]
        var perCategoryOverCount: [String: Int]
        var confidenceCalibrationOffset: Double
        var perCategoryThreshold: [String: Double]
        var totalCorrections: Int
        var lastRecomputeAt: Date?
    }

    private func snapshot() -> Snapshot {
        Snapshot(perCategoryAccuracy: perCategoryAccuracy,
                 perCategoryUnderCount: perCategoryUnderCount,
                 perCategoryOverCount: perCategoryOverCount,
                 confidenceCalibrationOffset: confidenceCalibrationOffset,
                 perCategoryThreshold: perCategoryThreshold,
                 totalCorrections: totalCorrections,
                 lastRecomputeAt: lastRecomputeAt)
    }

    private func apply(_ s: Snapshot) {
        perCategoryAccuracy = s.perCategoryAccuracy
        perCategoryUnderCount = s.perCategoryUnderCount
        perCategoryOverCount = s.perCategoryOverCount
        confidenceCalibrationOffset = s.confidenceCalibrationOffset
        perCategoryThreshold = s.perCategoryThreshold
        totalCorrections = s.totalCorrections
        lastRecomputeAt = s.lastRecomputeAt
    }

    func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot()) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let s = try? decoder.decode(Snapshot.self, from: data) {
            apply(s)
        }
    }
}
