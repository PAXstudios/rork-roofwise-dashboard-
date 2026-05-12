import Foundation

// MARK: - Phase 9 Recursive Learning Models
//
// Inspector-supplied corrections to AI detections. Persisted to JSON in
// Documents and consumed by `LocalLearningEngine` to tune per-user
// detection thresholds. All types are `nonisolated` Codable DTOs.

nonisolated enum CorrectionType: String, Codable, Hashable, Sendable, CaseIterable {
    case confirmed
    case rejected
    case edited
    case addedMissed = "added_missed"
    case removedFalsePositive = "removed_false_positive"

    var displayName: String {
        switch self {
        case .confirmed: return "Confirmed"
        case .rejected: return "Rejected"
        case .edited: return "Edited"
        case .addedMissed: return "Added missing"
        case .removedFalsePositive: return "Removed false positive"
        }
    }
}

nonisolated enum CorrectionSyncStatus: String, Codable, Hashable, Sendable {
    case pending, synced, failed
}

/// A single inspector edit on an existing AI marker. Stored inside a
/// `DetectionDelta`.
nonisolated struct DetectionDeltaOp: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case added
        case moved
        case resized
        case deleted
        case recategorized
    }
    let kind: Kind
    /// Marker id this op targets. New markers (kind == .added) get a fresh UUID.
    let markerId: UUID
    let x: Double?
    let y: Double?
    let radius: Double?
    let category: String?
    let severity: String?
    let note: String?
}

nonisolated struct DetectionDelta: Codable, Hashable, Sendable {
    var ops: [DetectionDeltaOp]

    init(ops: [DetectionDeltaOp] = []) {
        self.ops = ops
    }

    var isEmpty: Bool { ops.isEmpty }
    var addedCount: Int { ops.filter { $0.kind == .added }.count }
    var deletedCount: Int { ops.filter { $0.kind == .deleted }.count }
}

/// Frozen snapshot of an AI analysis result. Encoded as `Data` payload
/// inside a `Correction` for full reproducibility.
nonisolated struct CorrectionDetectionSnapshot: Codable, Hashable, Sendable {
    struct MarkerSnap: Codable, Hashable, Sendable {
        let id: UUID
        let category: String
        let severity: String
        let x: Double
        let y: Double
        let radius: Double
        let confidence: Int
        let note: String
    }
    struct FindingSnap: Codable, Hashable, Sendable {
        let label: String
        let confidence: Int
        let detected: Bool
        let severity: String
    }
    let markers: [MarkerSnap]
    let findings: [FindingSnap]
}

nonisolated struct Correction: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let inspectionId: UUID
    let photoId: UUID
    let slopeId: UUID?
    /// Encoded `CorrectionDetectionSnapshot` (JSON).
    let originalDetection: Data
    /// Encoded `CorrectionDetectionSnapshot` (JSON). Same shape after edits.
    let correctedDetection: Data
    let correctionType: CorrectionType
    let categoriesAffected: [String]
    /// Encoded `DetectionDelta` (JSON).
    let delta: Data
    let correctedBy: String
    let correctedAt: Date
    var syncStatus: CorrectionSyncStatus
    var syncFailureReason: String?

    init(id: UUID = UUID(),
         inspectionId: UUID,
         photoId: UUID,
         slopeId: UUID? = nil,
         originalDetection: Data,
         correctedDetection: Data,
         correctionType: CorrectionType,
         categoriesAffected: [String],
         delta: Data,
         correctedBy: String,
         correctedAt: Date = .now,
         syncStatus: CorrectionSyncStatus = .pending,
         syncFailureReason: String? = nil) {
        self.id = id
        self.inspectionId = inspectionId
        self.photoId = photoId
        self.slopeId = slopeId
        self.originalDetection = originalDetection
        self.correctedDetection = correctedDetection
        self.correctionType = correctionType
        self.categoriesAffected = categoriesAffected
        self.delta = delta
        self.correctedBy = correctedBy
        self.correctedAt = correctedAt
        self.syncStatus = syncStatus
        self.syncFailureReason = syncFailureReason
    }
}
