import Foundation
import Observation

/// Persisted queue of low-confidence damage detections that need human
/// review. Persists `[TrainingItem]` to `training-queue.json` in Documents.
@Observable
final class TrainingQueueStore {
    static let shared = TrainingQueueStore()

    private(set) var items: [TrainingItem] = []
    private let filename = "training-queue.json"

    init() { load() }

    // MARK: Queries

    var pending: [TrainingItem] {
        items.filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var pendingCount: Int { pending.count }

    var totalReviewed: Int {
        items.filter { $0.status != .pending }.count
    }

    /// Accuracy = (accepted) / (accepted + corrected + rejected). Returns
    /// nil if nothing reviewed yet.
    var accuracyPercent: Int? {
        let reviewed = items.filter { $0.status != .pending }
        guard !reviewed.isEmpty else { return nil }
        let accepted = reviewed.filter { $0.status == .accepted }.count
        return Int((Double(accepted) / Double(reviewed.count) * 100).rounded())
    }

    var lastReviewedAt: Date? {
        items.filter { $0.status != .pending }.map(\.createdAt).max()
    }

    // MARK: Enqueue

    /// Auto-enqueue rule per Phase 8: the parent `confidence_avg` must be < 0.6.
    /// Skips zero-count entries after that inspection/slope-level gate passes.
    @discardableResult
    func enqueueIfLowConfidence(reportId: String,
                                slopeOrientation: String,
                                kind: TrainingItem.Kind,
                                count: Int,
                                confidence: Double,
                                photoPath: String? = nil,
                                confidenceAvg: Double) -> TrainingItem? {
        guard count > 0 else { return nil }
        guard confidenceAvg < 0.6 else { return nil }
        // Dedup: don't re-enqueue an unresolved item for the same
        // (inspection, slope, kind).
        if items.contains(where: {
            $0.inspectionId == reportId &&
            $0.slopeOrientation == slopeOrientation &&
            $0.kind == kind &&
            $0.status == .pending
        }) {
            return nil
        }
        let item = TrainingItem(
            inspectionId: reportId,
            slopeOrientation: slopeOrientation,
            photoPath: photoPath,
            kind: kind,
            aiCount: count,
            aiConfidence: confidence
        )
        items.insert(item, at: 0)
        persist()
        return item
    }

    /// Run after a slope is saved. The old deterministic confidence stub is gone:
    /// we only enqueue when the AI snapshot's `confidence_avg` is below 0.6.
    func enqueueFromSlope(_ slope: Slope, on reportId: String) {
        guard let snapshot = slope.aiConfidenceSnapshot else { return }
        enqueueFromSnapshot(snapshot,
                            reportId: reportId,
                            slopeOrientation: slope.orientation)
    }

    func enqueueFromSnapshot(_ snapshot: AIDamageConfidenceSnapshot,
                             reportId: String,
                             slopeOrientation: String,
                             photoPath: String? = nil) {
        guard snapshot.confidenceAvg < 0.6 else { return }
        for category in snapshot.categories where category.count > 0 {
            _ = enqueueIfLowConfidence(
                reportId: reportId,
                slopeOrientation: slopeOrientation,
                kind: TrainingItem.Kind(category.kind),
                count: category.count,
                confidence: category.confidence,
                photoPath: photoPath,
                confidenceAvg: snapshot.confidenceAvg
            )
        }
    }

    // MARK: Mutations

    func accept(_ item: TrainingItem) {
        update(item.id) { $0.status = .accepted }
    }

    func correct(_ item: TrainingItem, override: Int) {
        update(item.id) {
            $0.status = .corrected
            $0.inspectorCountOverride = override
        }
    }

    func reject(_ item: TrainingItem) {
        update(item.id) { $0.status = .rejected }
    }

    private func update(_ id: UUID, mutate: (inout TrainingItem) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var copy = items[idx]
        mutate(&copy)
        items[idx] = copy
        persist()
    }

    // MARK: Persistence

    private var fileURL: URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        return docs.appendingPathComponent(filename)
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([TrainingItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func persist() {
        guard let url = fileURL else { return }
        do {
            let data = try makeEncoder().encode(items)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("TrainingQueueStore persist failed: \(error)")
            #endif
        }
    }
}

private extension TrainingItem.Kind {
    init(_ category: AIDamageCategoryKind) {
        switch category {
        case .hail: self = .hail
        case .wind: self = .wind
        case .wear: self = .wear
        case .missing: self = .missing
        }
    }
}
