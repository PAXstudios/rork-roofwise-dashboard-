import Foundation

nonisolated enum AIDamageCategoryKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case hail
    case wind
    case wear
    case missing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hail: return "HAIL"
        case .wind: return "WIND"
        case .wear: return "WEAR"
        case .missing: return "MISSING"
        }
    }
}

nonisolated enum AIDamageCategorySeverity: String, Codable, Hashable, Sendable {
    case minor
    case moderate
    case severe
}

nonisolated struct AIDamageCategoryConfidence: Codable, Identifiable, Hashable, Sendable {
    var id: AIDamageCategoryKind { kind }
    var kind: AIDamageCategoryKind
    var count: Int
    var confidence: Double
    var severity: AIDamageCategorySeverity

    init(kind: AIDamageCategoryKind,
         count: Int,
         confidence: Double,
         severity: AIDamageCategorySeverity) {
        self.kind = kind
        self.count = count
        self.confidence = max(0, min(1, confidence))
        self.severity = severity
    }
}

nonisolated struct AIDamageConfidenceSnapshot: Codable, Hashable, Sendable {
    var categories: [AIDamageCategoryConfidence]
    var confidenceAvg: Double

    init(categories: [AIDamageCategoryConfidence], confidenceAvg: Double? = nil) {
        self.categories = categories
        if let confidenceAvg {
            self.confidenceAvg = max(0, min(1, confidenceAvg))
        } else if categories.isEmpty {
            self.confidenceAvg = 0
        } else {
            self.confidenceAvg = categories.reduce(0) { $0 + $1.confidence } / Double(categories.count)
        }
    }

    enum CodingKeys: String, CodingKey {
        case categories
        case confidenceAvg = "confidence_avg"
    }

    static let empty = AIDamageConfidenceSnapshot(categories: AIDamageCategoryKind.allCases.map {
        AIDamageCategoryConfidence(kind: $0, count: 0, confidence: 0, severity: .minor)
    }, confidenceAvg: 0)

    func confidence(for kind: AIDamageCategoryKind) -> Double? {
        categories.first { $0.kind == kind }?.confidence
    }

    func count(for kind: AIDamageCategoryKind) -> Int {
        categories.first { $0.kind == kind }?.count ?? 0
    }

    static func merged(_ snapshots: [AIDamageConfidenceSnapshot]) -> AIDamageConfidenceSnapshot? {
        let valid = snapshots.filter { !$0.categories.isEmpty }
        guard !valid.isEmpty else { return nil }
        let categories = AIDamageCategoryKind.allCases.map { kind in
            let matches = valid.compactMap { snapshot in
                snapshot.categories.first { $0.kind == kind }
            }
            let totalCount = matches.reduce(0) { $0 + $1.count }
            let avgConfidence = matches.isEmpty ? 0 : matches.reduce(0) { $0 + $1.confidence } / Double(matches.count)
            let severity = matches.sorted { lhs, rhs in
                severityRank(lhs.severity) > severityRank(rhs.severity)
            }.first?.severity ?? .minor
            return AIDamageCategoryConfidence(kind: kind,
                                              count: totalCount,
                                              confidence: avgConfidence,
                                              severity: severity)
        }
        let avg = valid.reduce(0) { $0 + $1.confidenceAvg } / Double(valid.count)
        return AIDamageConfidenceSnapshot(categories: categories, confidenceAvg: avg)
    }

    private static func severityRank(_ severity: AIDamageCategorySeverity) -> Int {
        switch severity {
        case .minor: return 0
        case .moderate: return 1
        case .severe: return 2
        }
    }
}
