import Foundation
import Observation

/// Phase 9D learning engine. Reads `CorrectionsStore` history, recomputes
/// per-category accuracy + threshold offsets, and feeds them to:
/// - `TrainingQueueStore` (per-category enqueue threshold override)
/// - `GeminiAnalysisService` (user-style prompt prefix, append-only)
/// All compute is local to the device; no network. Strictly additive.
@Observable
final class LocalLearningEngine {
    static let shared = LocalLearningEngine()

    /// Base enqueue threshold (0-100). When the analyzer reports mean
    /// confidence below this, we surface for review.
    static let baseThreshold: Double = 60.0

    /// Rolling window of corrections used for stats.
    static let rollingWindow: Int = 100

    /// Minimum corrections before the user-style prompt prefix activates.
    static let promptPrefixMinCorrections: Int = 20

    private(set) var profile = UserCorrectionProfile()

    init() {
        // Initial compute against any persisted corrections.
        recomputeFromStore()
    }

    // MARK: Recompute

    /// Recompute rolling stats from the latest `CorrectionsStore` history.
    /// Emits an `aiCalibrationUpdated` activity event when any per-category
    /// threshold changes by ≥ 0.5%.
    func recomputeFromStore() {
        let recent = CorrectionsStore.shared.recent(Self.rollingWindow)
        var accuracy: [String: (correct: Int, total: Int)] = [:]
        var under: [String: Int] = [:]
        var over: [String: Int] = [:]

        for c in recent {
            for cat in c.categoriesAffected {
                var entry = accuracy[cat, default: (0, 0)]
                entry.total += 1
                if c.correctionType == .confirmed {
                    entry.correct += 1
                }
                accuracy[cat] = entry
                if c.correctionType == .addedMissed {
                    under[cat, default: 0] += 1
                }
                if c.correctionType == .removedFalsePositive {
                    over[cat, default: 0] += 1
                }
            }
        }

        var perCatAccuracy: [String: Double] = [:]
        for (cat, v) in accuracy {
            perCatAccuracy[cat] = v.total > 0 ? Double(v.correct) / Double(v.total) : 0
        }

        // Calibration offset: signed difference between under-add and over-remove
        // counts, normalized by rolling window size. Negative → user adds, raise
        // sensitivity (lower threshold). Positive → user removes, lower sensitivity.
        let underTotal = under.values.reduce(0, +)
        let overTotal = over.values.reduce(0, +)
        let denom = Double(max(Self.rollingWindow, 1))
        let calibration = Double(overTotal - underTotal) / denom

        // Per-category threshold: base + per-category signed pressure (-15..+15).
        var perCatThreshold: [String: Double] = [:]
        let allCats = Set(perCatAccuracy.keys).union(under.keys).union(over.keys)
        for cat in allCats {
            let u = Double(under[cat] ?? 0)
            let o = Double(over[cat] ?? 0)
            let signed = (o - u) / max(1.0, Double(recent.count))
            let offset = (signed * 30.0).clamped(to: -15.0...15.0)
            perCatThreshold[cat] = (Self.baseThreshold + offset).clamped(to: 30.0...85.0)
        }

        let previous = profile.perCategoryThreshold

        profile.perCategoryAccuracy = perCatAccuracy
        profile.perCategoryUnderCount = under
        profile.perCategoryOverCount = over
        profile.confidenceCalibrationOffset = calibration
        profile.perCategoryThreshold = perCatThreshold
        profile.totalCorrections = CorrectionsStore.shared.totalCount
        profile.lastRecomputeAt = .now
        profile.persist()

        // Emit calibration-updated activity events when threshold moved by ≥ 0.5%.
        for (cat, newVal) in perCatThreshold {
            let oldVal = previous[cat] ?? Self.baseThreshold
            let delta = newVal - oldVal
            if abs(delta) >= 0.5 {
                ActivityStore.shared.logCalibrationUpdate(category: cat, delta: delta)
            }
        }
    }

    // MARK: Public API consumed elsewhere

    /// Effective enqueue/verify threshold for a category. `nil` returns base.
    /// Used by `TrainingQueueStore` for per-user override.
    func effectiveThreshold(forCategory category: String?) -> Double {
        guard let category, let v = profile.perCategoryThreshold[category] else {
            return Self.baseThreshold
        }
        return v
    }

    /// Threshold delta for a category since the previous recompute, in
    /// percentage points (0-100 scale). Used for the per-save toast.
    func thresholdDelta(forCategory category: String, previous: Double?) -> Double {
        let current = effectiveThreshold(forCategory: category)
        let prev = previous ?? Self.baseThreshold
        return current - prev
    }

    /// One-line user-style prompt prefix prepended to the Gemini system
    /// prompt. Empty when total corrections < 20.
    func userStylePromptPrefix() -> String {
        guard profile.totalCorrections >= Self.promptPrefixMinCorrections else { return "" }
        let under = profile.perCategoryUnderCount
        let over = profile.perCategoryOverCount

        let topUnder = under.max(by: { $0.value < $1.value })
        let topOver = over.max(by: { $0.value < $1.value })

        var bits: [String] = []
        if let u = topUnder, u.value >= 3 {
            bits.append("Inspector tends to add \(prettyCategory(u.key)) damage AI misses; bias slightly toward \(prettyCategory(u.key)) detection.")
        }
        if let o = topOver, o.value >= 3 {
            bits.append("Inspector tends to remove false-positive \(prettyCategory(o.key)) markers; be conservative on \(prettyCategory(o.key)).")
        }
        return bits.joined(separator: " ")
    }

    private func prettyCategory(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
