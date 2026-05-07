import Foundation
import Observation

@Observable
final class LocalLearningEngine {
    static let shared = LocalLearningEngine()

    private(set) var profile: UserCorrectionProfile = .empty
    private let filename = "user-correction-profile.json"

    private init() { load() }

    var correctionsRecorded: Int { profile.totalCorrections }

    var accuracyPercent: Int {
        Int((profile.overallAccuracy * 100).rounded())
    }

    var weeklyLiftPercent: Int {
        let flagRate = profile.reviewFlagRate
        guard profile.totalCorrections > 0 else { return 0 }
        return max(1, Int((min(0.18, flagRate * 0.32) * 100).rounded()))
    }

    var deltaSummary: String {
        AIDamageCategoryKind.allCases.map { kind in
            let delta = thresholdDelta(for: kind)
            let sign = delta >= 0 ? "+" : ""
            return "\(kind.displayName) \(sign)\(Int((delta * 100).rounded()))pt"
        }.joined(separator: " · ")
    }

    var autoQueueThreshold: Double {
        profile.reviewFlagRate >= 0.40 ? 0.70 : max(0.52, min(0.68, 0.60 - profile.confidenceCalibrationOffset))
    }

    func adjustedSnapshot(_ snapshot: AIDamageConfidenceSnapshot) -> AIDamageConfidenceSnapshot {
        let categories = snapshot.categories.map { category in
            let delta = thresholdDelta(for: category.kind)
            return AIDamageCategoryConfidence(
                kind: category.kind,
                count: category.count,
                confidence: category.confidence + delta,
                severity: category.severity
            )
        }
        let avg = categories.isEmpty ? snapshot.confidenceAvg : categories.reduce(0) { $0 + $1.confidence } / Double(categories.count)
        return AIDamageConfidenceSnapshot(categories: categories, confidenceAvg: avg)
    }

    func thresholdDelta(for kind: AIDamageCategoryKind) -> Double {
        guard profile.totalCorrections > 0 else { return 0 }
        let affected = max(1, profile.samples.filter { sample in
            sample.categories.contains { $0.aiKind == kind }
        }.count)
        let underRatio = Double(profile.underCount(for: kind)) / Double(affected)
        let overRatio = Double(profile.overCount(for: kind)) / Double(affected)
        let categoryDelta = (underRatio * 0.18) - (overRatio * 0.30)
        return max(-0.30, min(0.24, categoryDelta + profile.confidenceCalibrationOffset))
    }

    func promptHints() -> String {
        guard profile.totalCorrections > 0 else {
            return "No user calibration history yet. Use conservative HAAG-style detection."
        }
        var hints: [String] = ["Calibrate to this inspector's last \(profile.totalCorrections) corrections."]
        for kind in AIDamageCategoryKind.allCases {
            let under = profile.underCount(for: kind)
            let over = profile.overCount(for: kind)
            if under >= max(2, over + 1) {
                hints.append("Inspector tends to identify \(kind.rawValue) damage the AI misses; bias toward careful \(kind.rawValue) detection when pixel evidence exists.")
            } else if over >= max(2, under + 1) {
                hints.append("Inspector often removes \(kind.rawValue) false positives; be more conservative for \(kind.rawValue) markers.")
            }
        }
        return hints.joined(separator: " ")
    }

    func improvementText(for categories: [ReviewDamageCategory]) -> String? {
        guard let first = categories.first else { return nil }
        let delta = thresholdDelta(for: first.aiKind)
        guard abs(delta) > 0.005 else { return nil }
        let direction = delta > 0 ? "missed" : "false-positive"
        return "Thanks — this helped improve \(first.displayName.lowercased()) \(direction) detection by \(abs(Int((delta * 100).rounded())))%."
    }

    func record(_ correction: CorrectionExport) {
        var profile = profile
        var samples = profile.samples
        samples.insert(CorrectionProfileSample(categories: correction.categoriesAffected,
                                               type: correction.correctionType,
                                               delta: correction.delta,
                                               correctedAt: correction.correctedAt), at: 0)
        samples = Array(samples.prefix(100))
        profile.samples = samples
        profile.perCategoryAccuracy = computeAccuracy(samples)
        profile.perCategoryUnderCount = computeCounts(samples, under: true)
        profile.perCategoryOverCount = computeCounts(samples, under: false)
        profile.confidenceCalibrationOffset = computeCalibrationOffset(samples)
        profile.updatedAt = .now
        self.profile = profile
        persist()
    }

    private func computeAccuracy(_ samples: [CorrectionProfileSample]) -> [String: Double] {
        var output: [String: Double] = [:]
        for kind in AIDamageCategoryKind.allCases {
            let matches = samples.filter { sample in sample.categories.contains { $0.aiKind == kind } }
            guard !matches.isEmpty else { continue }
            let confirmed = matches.filter { $0.type == .confirmed }.count
            output[kind.rawValue] = Double(confirmed) / Double(matches.count)
        }
        return output
    }

    private func computeCounts(_ samples: [CorrectionProfileSample], under: Bool) -> [String: Int] {
        var counts: [String: Int] = [:]
        for sample in samples {
            let isUnder = sample.type == .addedMissed || sample.delta.operations.contains { $0.op == .added }
            let isOver = sample.type == .rejected || sample.type == .removedFalsePositive || sample.delta.operations.contains { $0.op == .deleted }
            guard under ? isUnder : isOver else { continue }
            for category in sample.categories {
                counts[category.aiKind.rawValue, default: 0] += 1
            }
        }
        return counts
    }

    private func computeCalibrationOffset(_ samples: [CorrectionProfileSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let confirmed = samples.filter { $0.type == .confirmed }.count
        let rejected = samples.filter { $0.type == .rejected || $0.type == .removedFalsePositive }.count
        let edited = samples.filter { $0.type == .edited || $0.type == .addedMissed }.count
        let raw = (Double(edited) * 0.08 - Double(rejected) * 0.10 + Double(confirmed) * 0.025) / Double(samples.count)
        return max(-0.12, min(0.12, raw))
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    private func load() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(UserCorrectionProfile.self, from: data) {
            profile = decoded
        }
    }

    private func persist() {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profile).write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("LocalLearningEngine persist failed: \(error)")
            #endif
        }
    }
}
