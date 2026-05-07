import Foundation
import Observation

@Observable
final class StormAlertStore {
    static let shared = StormAlertStore()

    private(set) var alerts: [StormAlert] = []
    private let filename = "storm_alerts.json"

    init() { load() }

    var unread: [StormAlert] { alerts.filter { !$0.isRead } }
    var unreadCount: Int { unread.count }

    /// Most recent active (.new + not snoozed/dismissed) alert by `createdAt`.
    var latestActiveAlert: StormAlert? {
        alerts
            .filter { $0.isActive }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first
    }

    /// Insert new alerts, deduped by (areaId + eventId). Returns count newly added.
    @discardableResult
    func ingest(_ incoming: [StormAlert]) -> Int {
        var added = 0
        for a in incoming {
            let key = "\(a.areaId.uuidString)|\(a.eventId)"
            let exists = alerts.contains {
                "\($0.areaId.uuidString)|\($0.eventId)" == key
            }
            if !exists {
                alerts.insert(a, at: 0)
                added += 1
            }
        }
        if added > 0 { persist() }
        return added
    }

    @discardableResult
    func append(_ alert: StormAlert) -> Bool {
        ingest([alert]) > 0
    }

    func markRead(id: UUID) {
        guard let idx = alerts.firstIndex(where: { $0.id == id }) else { return }
        if !alerts[idx].isRead {
            alerts[idx].isRead = true
            persist()
        }
    }

    func markAllRead() {
        var changed = false
        for i in alerts.indices where !alerts[i].isRead {
            alerts[i].isRead = true
            changed = true
        }
        if changed { persist() }
    }

    func markActedOn(id: UUID) {
        guard let idx = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[idx].status = .actedOn
        alerts[idx].isRead = true
        persist()
    }

    func dismiss(id: UUID) {
        guard let idx = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[idx].status = .dismissed
        alerts[idx].isRead = true
        persist()
    }

    func snooze(id: UUID, until: Date) {
        guard let idx = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[idx].status = .snoozed
        alerts[idx].snoozedUntil = until
        persist()
    }

    func remove(id: UUID) {
        alerts.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        guard !alerts.isEmpty else { return }
        alerts.removeAll()
        persist()
    }

    // MARK: Persistence

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(filename)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let arr = try? dec.decode([StormAlert].self, from: data) {
            alerts = arr
        }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(alerts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
