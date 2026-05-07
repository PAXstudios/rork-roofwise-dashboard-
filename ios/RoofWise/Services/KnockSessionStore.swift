import Foundation
import Observation

/// Source-of-truth store for door-knocking routes (`KnockSession`s) and the
/// individual `Knock`s logged inside each one. Persists the full array as
/// JSON in the app's Documents directory at `knock-sessions.json`.
@Observable
final class KnockSessionStore {
    static let shared = KnockSessionStore()

    private(set) var sessions: [KnockSession] = []

    private let filename = "knock-sessions.json"

    init() {
        load()
    }

    // MARK: - Helpers

    /// The currently-open session, if any (i.e. ended_at == nil).
    var currentSession: KnockSession? {
        sessions.first { $0.ended_at == nil }
    }

    /// Starts a new session and returns it. If another session is already open,
    /// it is closed first so only one session is ever active.
    @discardableResult
    func startSession(stormAlertId: String? = nil) -> KnockSession {
        if let open = currentSession {
            endSession(id: open.id)
        }
        let s = KnockSession(route_storm_alert_id: stormAlertId)
        sessions.append(s)
        save()
        return s
    }

    /// Appends a knock to the session with the given id. No-op if the session
    /// doesn't exist.
    func append(knock: Knock, to sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].knocks.append(knock)
        save()
    }

    /// Closes the session by stamping `ended_at`. No-op if already closed.
    func endSession(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard sessions[idx].ended_at == nil else { return }
        sessions[idx].ended_at = Date()
        save()
    }

    /// Stamps the `created_lead_id` on a knock so the route summary can show
    /// how many leads were minted in the field.
    func setCreatedLead(_ leadId: String, knockId: UUID, sessionId: UUID) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard let kIdx = sessions[sIdx].knocks.firstIndex(where: { $0.id == knockId }) else { return }
        sessions[sIdx].knocks[kIdx].created_lead_id = leadId
        save()
    }

    func session(with id: UUID) -> KnockSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Persistence

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
              let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? makeDecoder().decode([KnockSession].self, from: data) {
            sessions = decoded
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            let data = try makeEncoder().encode(sessions)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("KnockSessionStore save failed: \(error)")
            #endif
        }
    }
}
