import Foundation
import UIKit

enum ReviewPhotoFactory {
    static func pendingQueueItems() -> [ReviewPhotoItem] {
        TrainingQueueStore.shared.pending.map { item in
            let category = item.kind.reviewCategory
            let confidence = AIDamageCategoryConfidence(
                kind: category.aiKind,
                count: item.aiCount,
                confidence: item.aiConfidence,
                severity: item.aiConfidence < 0.45 ? .severe : .moderate
            )
            let snapshot = AIDamageConfidenceSnapshot(
                categories: AIDamageCategoryKind.allCases.map { kind in
                    kind == category.aiKind ? confidence : AIDamageCategoryConfidence(kind: kind, count: 0, confidence: max(0.62, item.aiConfidence), severity: .minor)
                },
                confidenceAvg: item.aiConfidence
            )
            return ReviewPhotoItem(
                inspectionId: item.inspectionId,
                photoId: item.id.uuidString,
                slopeId: item.slopeOrientation,
                slopeLabel: item.slopeOrientation,
                image: nil,
                trainingItemId: item.id,
                snapshot: snapshot,
                markers: ReviewPhotoItem.syntheticMarkers(from: snapshot)
            )
        }
    }

    static func items(for inspection: Inspection, store: InspectionStore = .shared) -> [ReviewPhotoItem] {
        inspection.slopes.compactMap { slope in
            guard let snapshot = slope.aiConfidenceSnapshot else { return nil }
            let image = store.photos(for: inspection.id, orientation: slope.orientation).first
            return ReviewPhotoItem(
                inspectionId: inspection.id,
                photoId: "\(inspection.id)-\(slope.orientation)",
                slopeId: slope.orientation,
                slopeLabel: slope.orientation,
                image: image,
                snapshot: snapshot,
                markers: ReviewPhotoItem.syntheticMarkers(from: snapshot)
            )
        }
    }
}
