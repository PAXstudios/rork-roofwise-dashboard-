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

    /// Auto-enqueue rule per spec: ai_confidence < 0.6 OR ai_count > 10
    /// (potential hallucination). Skips zero-count entries.
    @discardableResult
    func enqueueIfLowConfidence(reportId: String,
                                slopeOrientation: String,
                                kind: TrainingItem.Kind,
                                count: Int,
                                confidence: Double,
                                photoPath: String? = nil) -> TrainingItem? {
        guard count > 0 else { return nil }
        guard confidence < 0.6 || count > 10 else { return nil }
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

    /// Run after a slope is saved. Walks every damage category and feeds
    /// the auto-enqueue rule. Confidence is derived deterministically from
    /// the count (the existing capture pipeline does NOT yet surface a per-
    /// category confidence) so the queue still receives a realistic mix
    /// without changing the on-disk schema.
    func enqueueFromSlope(_ slope: Slope, on reportId: String) {
        let pairs: [(TrainingItem.Kind, Int)] = [
            (.hailBruise,   slope.damageTypes.hail.asphaltBruise),
            (.hailFracture, slope.damageTypes.hail.asphaltMatFracture),
            (.hailGranule,  slope.damageTypes.hail.asphaltGranuleLossExposed),
            (.windCrease,   slope.damageTypes.wind.shingleCrease),
            (.windMissing,  slope.damageTypes.wind.shingleMissing),
            (.windLifted,   slope.damageTypes.wind.shingleLiftedUnsealed)
        ]
        for (kind, count) in pairs {
            guard count > 0 else { continue }
            let confidence = Self.mockConfidence(for: kind, count: count, orientation: slope.orientation)
            _ = enqueueIfLowConfidence(
                reportId: reportId,
                slopeOrientation: slope.orientation,
                kind: kind,
                count: count,
                confidence: confidence
            )
        }
    }

    /// Deterministic mock confidence: high counts + categories prone to
    /// false-positives (granule loss, lifted shingles) sit lower. Always in
    /// (0.30, 0.95).
    static func mockConfidence(for kind: TrainingItem.Kind,
                               count: Int,
                               orientation: String) -> Double {
        let base: Double
        switch kind {
        case .hailBruise:   base = 0.78
        case .hailFracture: base = 0.82
        case .hailGranule:  base = 0.55     // intentionally borderline
        case .windCrease:   base = 0.74
        case .windMissing:  base = 0.86
        case .windLifted:   base = 0.52     // intentionally borderline
        }
        // Penalty grows with count (very-high counts often == hallucination).
        let penalty = min(0.35, Double(count) / 30.0)
        // Tiny jitter from orientation hash so two slopes don't read identical.
        let jitter = (Double(abs(orientation.hashValue % 17)) - 8) / 200.0
        return max(0.30, min(0.95, base - penalty + jitter))
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
