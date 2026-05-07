import Foundation

nonisolated struct CorrectionProfileSample: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var categories: [ReviewDamageCategory]
    var type: CorrectionType
    var delta: DetectionDelta
    var correctedAt: Date

    init(id: UUID = UUID(),
         categories: [ReviewDamageCategory],
         type: CorrectionType,
         delta: DetectionDelta,
         correctedAt: Date = .now) {
        self.id = id
        self.categories = categories
        self.type = type
        self.delta = delta
        self.correctedAt = correctedAt
    }
}

nonisolated struct UserCorrectionProfile: Codable, Hashable, Sendable {
    var perCategoryAccuracy: [String: Double]
    var perCategoryUnderCount: [String: Int]
    var perCategoryOverCount: [String: Int]
    var confidenceCalibrationOffset: Double
    var samples: [CorrectionProfileSample]
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case perCategoryAccuracy = "per_category_accuracy"
        case perCategoryUnderCount = "per_category_under_count"
        case perCategoryOverCount = "per_category_over_count"
        case confidenceCalibrationOffset = "confidence_calibration_offset"
        case samples
        case updatedAt = "updated_at"
    }

    static let empty = UserCorrectionProfile(
        perCategoryAccuracy: [:],
        perCategoryUnderCount: [:],
        perCategoryOverCount: [:],
        confidenceCalibrationOffset: 0,
        samples: [],
        updatedAt: .now
    )

    var totalCorrections: Int { samples.count }

    var confirmedCount: Int {
        samples.filter { $0.type == .confirmed }.count
    }

    var editedCount: Int {
        samples.filter { $0.type == .edited || $0.type == .addedMissed }.count
    }

    var falsePositiveCount: Int {
        samples.filter { $0.type == .rejected || $0.type == .removedFalsePositive }.count
    }

    var reviewFlagRate: Double {
        guard !samples.isEmpty else { return 0 }
        return Double(editedCount + falsePositiveCount) / Double(samples.count)
    }

    var overallAccuracy: Double {
        guard !samples.isEmpty else { return 0.82 }
        return Double(confirmedCount) / Double(samples.count)
    }

    var weeklyCorrectionCount: Int {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return samples.filter { $0.correctedAt >= weekAgo }.count
    }

    func accuracy(for kind: AIDamageCategoryKind) -> Double? {
        perCategoryAccuracy[kind.rawValue]
    }

    func underCount(for kind: AIDamageCategoryKind) -> Int {
        perCategoryUnderCount[kind.rawValue] ?? 0
    }

    func overCount(for kind: AIDamageCategoryKind) -> Int {
        perCategoryOverCount[kind.rawValue] ?? 0
    }
}
