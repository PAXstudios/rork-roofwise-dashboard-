import Foundation
import Observation

/// Phase 9 corrections store. Persists `[Correction]` as JSON in Documents.
/// Provides counts grouped by category and sync-state mutations.
@Observable
final class CorrectionsStore {
    static let shared = CorrectionsStore()

    private(set) var items: [Correction] = []
    private let filename = "corrections.json"

    /// Stable per-install identifier used as `correctedBy`. Stored in
    /// UserDefaults so the same user appears stable across launches.
    static var localUserId: String {
        let key = "rw.correction.user.uuid"
        if let s = UserDefaults.standard.string(forKey: key) { return s }
        let s = UUID().uuidString
        UserDefaults.standard.set(s, forKey: key)
        return s
    }

    init() { load() }

    // MARK: Queries

    var totalCount: Int { items.count }

    func counts(byCategory category: String) -> Int {
        items.filter { $0.categoriesAffected.contains(category) }.count
    }

    func countsGroupedByCategory() -> [String: Int] {
        var dict: [String: Int] = [:]
        for c in items {
            for cat in c.categoriesAffected {
                dict[cat, default: 0] += 1
            }
        }
        return dict
    }

    func pendingForSync() -> [Correction] {
        items.filter { $0.syncStatus == .pending }
    }

    /// Most recent N corrections in reverse chronological order.
    func recent(_ limit: Int = 100) -> [Correction] {
        items.sorted { $0.correctedAt > $1.correctedAt }.prefix(limit).map { $0 }
    }

    /// Corrections in the last `days` days.
    func recent(days: Int) -> [Correction] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return items.filter { $0.correctedAt >= cutoff }
    }

    // MARK: Mutations

    @discardableResult
    func append(_ correction: Correction) -> Correction {
        items.insert(correction, at: 0)
        persist()
        // Surface to learning engine + outbox.
        LocalLearningEngine.shared.recomputeFromStore()
        CorrectionsSyncService.shared.enqueueOutbox(correction)
        return correction
    }

    func markSynced(ids: [UUID]) {
        let set = Set(ids)
        for i in items.indices where set.contains(items[i].id) {
            items[i].syncStatus = .synced
            items[i].syncFailureReason = nil
        }
        persist()
    }

    func markFailed(ids: [UUID], reason: String) {
        let set = Set(ids)
        for i in items.indices where set.contains(items[i].id) {
            items[i].syncStatus = .failed
            items[i].syncFailureReason = reason
        }
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
              let decoded = try? makeDecoder().decode([Correction].self, from: data) else {
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
            print("CorrectionsStore persist failed: \(error)")
            #endif
        }
    }
}

// MARK: - Helpers for building Correction snapshots

extension CorrectionsStore {
    /// Encodes a `CorrectionDetectionSnapshot` to JSON `Data`.
    static func encode(_ snapshot: CorrectionDetectionSnapshot) -> Data {
        (try? JSONEncoder().encode(snapshot)) ?? Data()
    }

    /// Encodes a `DetectionDelta` to JSON `Data`.
    static func encode(_ delta: DetectionDelta) -> Data {
        (try? JSONEncoder().encode(delta)) ?? Data()
    }

    /// Decodes a `CorrectionDetectionSnapshot` from JSON `Data`.
    static func decodeSnapshot(_ data: Data) -> CorrectionDetectionSnapshot? {
        try? JSONDecoder().decode(CorrectionDetectionSnapshot.self, from: data)
    }

    /// Decodes a `DetectionDelta` from JSON `Data`.
    static func decodeDelta(_ data: Data) -> DetectionDelta? {
        try? JSONDecoder().decode(DetectionDelta.self, from: data)
    }
}

// MARK: - Snapshot adapter

extension CorrectionDetectionSnapshot {
    static func from(findings: [InspectionFinding], markers: [DamageMarker]) -> CorrectionDetectionSnapshot {
        CorrectionDetectionSnapshot(
            markers: markers.map { m in
                MarkerSnap(id: m.id,
                           category: m.type.rawValue,
                           severity: m.severity.rawValue,
                           x: Double(m.x),
                           y: Double(m.y),
                           radius: Double(m.radius),
                           confidence: m.confidence,
                           note: m.note)
            },
            findings: findings.map { f in
                FindingSnap(label: f.label,
                            confidence: f.confidence,
                            detected: f.detected,
                            severity: f.severity.rawValue)
            }
        )
    }
}
