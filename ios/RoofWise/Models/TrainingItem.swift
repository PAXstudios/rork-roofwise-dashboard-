import Foundation

/// A single low-confidence damage detection awaiting human review. Surfaced
/// in the Train tab's "Pending review" queue. Pure data.
nonisolated struct TrainingItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let inspectionId: String
    let slopeOrientation: String
    let photoPath: String?
    let kind: Kind
    let aiCount: Int
    let aiConfidence: Double
    var status: Status
    var inspectorCountOverride: Int?
    let createdAt: Date

    init(id: UUID = UUID(),
         inspectionId: String,
         slopeOrientation: String,
         photoPath: String? = nil,
         kind: Kind,
         aiCount: Int,
         aiConfidence: Double,
         status: Status = .pending,
         inspectorCountOverride: Int? = nil,
         createdAt: Date = .now) {
        self.id = id
        self.inspectionId = inspectionId
        self.slopeOrientation = slopeOrientation
        self.photoPath = photoPath
        self.kind = kind
        self.aiCount = aiCount
        self.aiConfidence = aiConfidence
        self.status = status
        self.inspectorCountOverride = inspectorCountOverride
        self.createdAt = createdAt
    }

    enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case hail
        case wind
        case wear
        case missing
        case hailBruise = "hail_bruise"
        case hailFracture = "hail_fracture"
        case hailGranule = "hail_granule"
        case windCrease = "wind_crease"
        case windMissing = "wind_missing"
        case windLifted = "wind_lifted"

        var displayName: String {
            switch self {
            case .hail:         return "Hail indicators"
            case .wind:         return "Wind indicators"
            case .wear:         return "Wear indicators"
            case .missing:      return "Missing shingles"
            case .hailBruise:   return "Hail bruise"
            case .hailFracture: return "Hail mat fracture"
            case .hailGranule:  return "Granule loss"
            case .windCrease:   return "Wind crease"
            case .windMissing:  return "Missing shingle"
            case .windLifted:   return "Lifted/unsealed"
            }
        }

        var icon: String {
            switch self {
            case .hail, .hailBruise, .hailFracture, .hailGranule:
                return "circle.hexagongrid.fill"
            case .wind, .windCrease, .windLifted:
                return "wind"
            case .wear:
                return "clock.arrow.circlepath"
            case .missing, .windMissing:
                return "square.dashed"
            }
        }
    }

    enum Status: String, Codable, Hashable, Sendable {
        case pending, accepted, corrected, rejected
    }

    enum CodingKeys: String, CodingKey {
        case id
        case inspectionId = "inspection_id"
        case slopeOrientation = "slope_orientation"
        case photoPath = "photo_path"
        case kind
        case aiCount = "ai_count"
        case aiConfidence = "ai_confidence"
        case status
        case inspectorCountOverride = "inspector_count_override"
        case createdAt = "created_at"
    }
}
