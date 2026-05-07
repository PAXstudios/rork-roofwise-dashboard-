import Foundation
import SwiftData
import CoreGraphics

nonisolated enum ReviewDamageCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case hail
    case wind
    case wear
    case missing
    case bruise
    case exposedMat = "exposed_mat"
    case lifted
    case torn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hail: return "Hail"
        case .wind: return "Wind"
        case .wear: return "Wear"
        case .missing: return "Missing"
        case .bruise: return "Bruise"
        case .exposedMat: return "Exposed Mat"
        case .lifted: return "Lifted"
        case .torn: return "Torn"
        }
    }

    var aiKind: AIDamageCategoryKind {
        switch self {
        case .hail, .bruise, .exposedMat: return .hail
        case .wind, .lifted, .torn: return .wind
        case .wear: return .wear
        case .missing: return .missing
        }
    }

    init(markerType: DamageMarkerType) {
        switch markerType {
        case .hailStrike: self = .hail
        case .shingleBruise: self = .bruise
        case .exposedMat: self = .exposedMat
        case .missingShingle: self = .missing
        case .liftedShingle: self = .lifted
        case .tornShingle: self = .torn
        case .windCrease: self = .wind
        case .granuleLoss, .blister, .algae: self = .wear
        case .crack, .flashing, .other: self = .wind
        }
    }

    var markerType: DamageMarkerType {
        switch self {
        case .hail: return .hailStrike
        case .wind: return .windCrease
        case .wear: return .granuleLoss
        case .missing: return .missingShingle
        case .bruise: return .shingleBruise
        case .exposedMat: return .exposedMat
        case .lifted: return .liftedShingle
        case .torn: return .tornShingle
        }
    }
}

nonisolated enum CorrectionType: String, Codable, CaseIterable, Hashable, Sendable {
    case confirmed
    case rejected
    case edited
    case addedMissed = "added_missed"
    case removedFalsePositive = "removed_false_positive"
}

nonisolated enum CorrectionSyncStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending
    case synced
    case failed
}

nonisolated enum MarkerOperationKind: String, Codable, Hashable, Sendable {
    case added
    case moved
    case resized
    case deleted
    case recategorized
}

nonisolated struct EditableDamageMarker: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var x: Double
    var y: Double
    var radius: Double
    var category: ReviewDamageCategory
    var severity: AIDamageCategorySeverity
    var note: String
    var confidence: Double

    init(id: UUID = UUID(),
         x: Double,
         y: Double,
         radius: Double,
         category: ReviewDamageCategory,
         severity: AIDamageCategorySeverity,
         note: String = "",
         confidence: Double = 0) {
        self.id = id
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
        self.radius = max(0.006, min(0.16, radius))
        self.category = category
        self.severity = severity
        self.note = note
        self.confidence = max(0, min(1, confidence))
    }

    init(marker: DamageMarker) {
        self.init(
            id: marker.id,
            x: Double(marker.x),
            y: Double(marker.y),
            radius: Double(marker.radius),
            category: ReviewDamageCategory(markerType: marker.type),
            severity: AIDamageCategorySeverity(findingSeverity: marker.severity),
            note: marker.note,
            confidence: Double(marker.confidence) / 100.0
        )
    }

    var damageMarker: DamageMarker {
        DamageMarker(
            x: CGFloat(x),
            y: CGFloat(y),
            radius: CGFloat(radius),
            type: category.markerType,
            severity: severity.findingSeverity,
            note: note,
            confidence: Int((confidence * 100).rounded())
        )
    }
}

nonisolated struct MarkerOperation: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var markerId: UUID
    var op: MarkerOperationKind
    var before: EditableDamageMarker?
    var after: EditableDamageMarker?
}

nonisolated struct DetectionDelta: Codable, Hashable, Sendable {
    var operations: [MarkerOperation]

    static let empty = DetectionDelta(operations: [])
}

nonisolated struct AIDetectionSnapshot: Codable, Hashable, Sendable {
    var categories: [AIDamageCategoryConfidence]
    var confidenceAvg: Double
    var markers: [EditableDamageMarker]
    var verdict: String

    enum CodingKeys: String, CodingKey {
        case categories
        case confidenceAvg = "confidence_avg"
        case markers
        case verdict
    }

    init(categories: [AIDamageCategoryConfidence],
         confidenceAvg: Double,
         markers: [EditableDamageMarker],
         verdict: String) {
        self.categories = categories
        self.confidenceAvg = max(0, min(1, confidenceAvg))
        self.markers = markers
        self.verdict = verdict
    }

    init(snapshot: AIDamageConfidenceSnapshot?, markers: [EditableDamageMarker], verdict: String) {
        let snapshot = snapshot ?? .empty
        self.init(categories: snapshot.categories,
                  confidenceAvg: snapshot.confidenceAvg,
                  markers: markers,
                  verdict: verdict)
    }
}

nonisolated struct CorrectionExport: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var inspectionId: String
    var photoId: String
    var slopeId: String?
    var originalDetection: AIDetectionSnapshot
    var correctedDetection: AIDetectionSnapshot
    var correctionType: CorrectionType
    var categoriesAffected: [ReviewDamageCategory]
    var delta: DetectionDelta
    var correctedBy: String
    var correctedAt: Date
    var syncStatus: CorrectionSyncStatus

    enum CodingKeys: String, CodingKey {
        case id
        case inspectionId = "inspection_id"
        case photoId = "photo_id"
        case slopeId = "slope_id"
        case originalDetection = "original_detection"
        case correctedDetection = "corrected_detection"
        case correctionType = "correction_type"
        case categoriesAffected = "categories_affected"
        case delta
        case correctedBy = "corrected_by"
        case correctedAt = "corrected_at"
        case syncStatus = "sync_status"
    }
}

@Model
final class Correction {
    @Attribute(.unique) var id: UUID
    var inspectionId: String
    var photoId: String
    var slopeId: String?
    var originalDetectionData: Data
    var correctedDetectionData: Data
    var correctionTypeRaw: String
    var categoriesAffectedData: Data
    var deltaData: Data
    var correctedBy: String
    var correctedAt: Date
    var syncStatusRaw: String

    init(id: UUID = UUID(),
         inspectionId: String,
         photoId: String,
         slopeId: String? = nil,
         originalDetection: AIDetectionSnapshot,
         correctedDetection: AIDetectionSnapshot,
         correctionType: CorrectionType,
         categoriesAffected: [ReviewDamageCategory],
         delta: DetectionDelta,
         correctedBy: String = InspectorUser.current.name,
         correctedAt: Date = .now,
         syncStatus: CorrectionSyncStatus = .pending) {
        self.id = id
        self.inspectionId = inspectionId
        self.photoId = photoId
        self.slopeId = slopeId
        self.originalDetectionData = Self.encode(originalDetection)
        self.correctedDetectionData = Self.encode(correctedDetection)
        self.correctionTypeRaw = correctionType.rawValue
        self.categoriesAffectedData = Self.encode(categoriesAffected)
        self.deltaData = Self.encode(delta)
        self.correctedBy = correctedBy
        self.correctedAt = correctedAt
        self.syncStatusRaw = syncStatus.rawValue
    }

    var correctionType: CorrectionType {
        get { CorrectionType(rawValue: correctionTypeRaw) ?? .edited }
        set { correctionTypeRaw = newValue.rawValue }
    }

    var syncStatus: CorrectionSyncStatus {
        get { CorrectionSyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    var originalDetection: AIDetectionSnapshot { Self.decode(AIDetectionSnapshot.self, from: originalDetectionData) ?? AIDetectionSnapshot(snapshot: .empty, markers: [], verdict: "") }
    var correctedDetection: AIDetectionSnapshot { Self.decode(AIDetectionSnapshot.self, from: correctedDetectionData) ?? originalDetection }
    var categoriesAffected: [ReviewDamageCategory] { Self.decode([ReviewDamageCategory].self, from: categoriesAffectedData) ?? [] }
    var delta: DetectionDelta { Self.decode(DetectionDelta.self, from: deltaData) ?? .empty }

    var export: CorrectionExport {
        CorrectionExport(id: id,
                         inspectionId: inspectionId,
                         photoId: photoId,
                         slopeId: slopeId,
                         originalDetection: originalDetection,
                         correctedDetection: correctedDetection,
                         correctionType: correctionType,
                         categoriesAffected: categoriesAffected,
                         delta: delta,
                         correctedBy: correctedBy,
                         correctedAt: correctedAt,
                         syncStatus: syncStatus)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}

private extension AIDamageCategorySeverity {
    init(findingSeverity: FindingSeverity) {
        switch findingSeverity {
        case .none, .minor: self = .minor
        case .moderate: self = .moderate
        case .severe: self = .severe
        }
    }

    var findingSeverity: FindingSeverity {
        switch self {
        case .minor: return .minor
        case .moderate: return .moderate
        case .severe: return .severe
        }
    }
}
