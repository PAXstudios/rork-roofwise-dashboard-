import Foundation
import UIKit

struct ReviewPhotoItem: Identifiable {
    let id: UUID
    let inspectionId: String
    let photoId: String
    let slopeId: String?
    let slopeLabel: String
    let image: UIImage?
    let trainingItemId: UUID?
    let snapshot: AIDamageConfidenceSnapshot
    let markers: [EditableDamageMarker]

    init(id: UUID = UUID(),
         inspectionId: String,
         photoId: String,
         slopeId: String?,
         slopeLabel: String,
         image: UIImage?,
         trainingItemId: UUID? = nil,
         snapshot: AIDamageConfidenceSnapshot,
         markers: [EditableDamageMarker]) {
        self.id = id
        self.inspectionId = inspectionId
        self.photoId = photoId
        self.slopeId = slopeId
        self.slopeLabel = slopeLabel
        self.image = image
        self.trainingItemId = trainingItemId
        self.snapshot = snapshot
        self.markers = markers
    }

    var verdict: String {
        if let top = snapshot.categories
            .filter({ $0.count > 0 })
            .sorted(by: { lhs, rhs in
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                return lhs.count > rhs.count
            })
            .first {
            return "\(top.kind.displayName) - \(top.count) hits - \(Int((top.confidence * 100).rounded()))% confidence"
        }
        return "NO DAMAGE - 0 hits - \(Int((snapshot.confidenceAvg * 100).rounded()))% confidence"
    }

    var originalDetection: AIDetectionSnapshot {
        AIDetectionSnapshot(snapshot: snapshot, markers: markers, verdict: verdict)
    }

    static func syntheticMarkers(from snapshot: AIDamageConfidenceSnapshot) -> [EditableDamageMarker] {
        let points: [(Double, Double)] = [
            (0.24, 0.30), (0.41, 0.24), (0.58, 0.35), (0.72, 0.46),
            (0.34, 0.56), (0.52, 0.62), (0.68, 0.70), (0.22, 0.74)
        ]
        var output: [EditableDamageMarker] = []
        var cursor = 0
        for category in snapshot.categories where category.count > 0 {
            let cap = min(category.count, 4)
            for _ in 0..<cap {
                let point = points[cursor % points.count]
                cursor += 1
                output.append(EditableDamageMarker(
                    x: point.0,
                    y: point.1,
                    radius: 0.026,
                    category: ReviewDamageCategory(aiKind: category.kind),
                    severity: category.severity,
                    note: "AI marker awaiting inspector review",
                    confidence: category.confidence
                ))
            }
        }
        return output
    }
}

extension ReviewDamageCategory {
    init(aiKind: AIDamageCategoryKind) {
        switch aiKind {
        case .hail: self = .hail
        case .wind: self = .wind
        case .wear: self = .wear
        case .missing: self = .missing
        }
    }
}

extension TrainingItem.Kind {
    var reviewCategory: ReviewDamageCategory {
        switch self {
        case .hail, .hailBruise, .hailFracture, .hailGranule:
            return .hail
        case .wind, .windCrease, .windLifted:
            return .wind
        case .wear:
            return .wear
        case .missing, .windMissing:
            return .missing
        }
    }
}
