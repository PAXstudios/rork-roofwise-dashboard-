import Foundation
import Observation

/// Per-inspection activity log. Each inspection's events live in their own
/// JSON file (`activity-<reportId>.json`) so a single store can power the
/// "Activity" sheet on JobDetailView without loading every inspection's
/// history at once.
@Observable
final class ActivityStore {
    static let shared = ActivityStore()

    /// In-memory cache keyed by inspection report id.
    private var cache: [String: [ActivityEvent]] = [:]

    init() {}

    // MARK: Public API

    /// Returns events for an inspection, newest first. Loads from disk on
    /// first access, then caches.
    func events(for reportId: String) -> [ActivityEvent] {
        if let cached = cache[reportId] { return cached }
        let loaded = load(reportId: reportId)
        cache[reportId] = loaded
        return loaded
    }

    /// Logs a single event against the supplied inspection.
    @discardableResult
    func log(_ kind: ActivityEvent.Kind,
             summary: String,
             detail: String? = nil,
             on inspection: Inspection) -> ActivityEvent {
        log(kind, summary: summary, detail: detail, reportId: inspection.id)
    }

    /// Same as the inspection-bound overload, for callers that only have
    /// the report id (e.g. async storm match).
    @discardableResult
    func log(_ kind: ActivityEvent.Kind,
             summary: String,
             detail: String? = nil,
             reportId: String) -> ActivityEvent {
        let event = ActivityEvent(
            inspectionId: reportId,
            kind: kind,
            summary: summary,
            detail: detail
        )
        var list = events(for: reportId)
        list.insert(event, at: 0)
        cache[reportId] = list
        persist(reportId: reportId, list: list)
        return event
    }

    /// Logs an AI calibration update from `LocalLearningEngine`. Stored under
    /// a shared `ai-calibration` bucket (no specific inspection).
    func logCalibrationUpdate(category: String, delta: Double) {
        let sign = delta >= 0 ? "+" : ""
        let summary = "AI threshold \(category) \(sign)\(String(format: "%.1f", delta))%"
        log(.aiCalibrationUpdated, summary: summary, reportId: "ai-calibration")
    }

    /// Logs a low-priority `.uiTap` event used by the broader tap-trace audit.
    /// Not bound to any inspection — stored under a shared `ui-tap` bucket.
    func logTap(target: String) {
        log(.uiTap, summary: target, reportId: "ui-tap")
    }

    /// Wipes log for a single inspection (used when the inspection itself is
    /// deleted; not currently auto-called).
    func clear(reportId: String) {
        cache[reportId] = []
        if let url = fileURL(reportId: reportId) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Persistence

    private func fileURL(reportId: String) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        // sanitize: report ids are like RW-2026-0001 — already safe, but be
        // defensive in case of free-form ids.
        let safe = reportId.replacingOccurrences(of: "/", with: "_")
        return docs.appendingPathComponent("activity-\(safe).json")
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

    private func load(reportId: String) -> [ActivityEvent] {
        guard let url = fileURL(reportId: reportId),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([ActivityEvent].self, from: data) else {
            return []
        }
        // Stored newest-first; if an older file isn't sorted, sort defensively.
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private func persist(reportId: String, list: [ActivityEvent]) {
        guard let url = fileURL(reportId: reportId) else { return }
        do {
            let data = try makeEncoder().encode(list)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("ActivityStore persist failed: \(error)")
            #endif
        }
    }
}
