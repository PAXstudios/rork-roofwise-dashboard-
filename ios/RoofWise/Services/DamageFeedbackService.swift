import Foundation
import Network
import Observation
import Supabase

/// Canonical writer for `public.damage_feedback` — the recursive-learning
/// signal produced by `EditDetectionView`. It maps 1:1 to the Phase 1 schema
/// (`ai_*` / `user_*` columns, required `inspection_photo_id` FK, 0–10 trust
/// scale) which is why this service supersedes the older correction-based
/// writer: only the editor holds the real `CapturedPhoto.id` needed for the FK.
///
/// Local-first & offline-tolerant: events are persisted to an on-disk outbox
/// the instant they're recorded, then flushed to Supabase. Anything that fails
/// (offline, FK not yet present, auth) stays queued and retries automatically
/// when connectivity returns or the app foregrounds. Upserts on `id` make
/// retries idempotent (no duplicate rows).
@Observable
@MainActor
final class DamageFeedbackService {
    static let shared = DamageFeedbackService()

    enum Status: Equatable {
        case idle
        case saving
        case saved(at: Date)
        case queued(count: Int)   // offline / failed — will retry
    }

    private(set) var status: Status = .idle

    private var queue: [DamageFeedbackEvent] = []
    private let filename = "damage_feedback_outbox.json"
    private let monitor = NWPathMonitor()
    private var isOnline = true
    private var flushing = false

    private init() {
        loadQueue()
        if !queue.isEmpty { status = .queued(count: queue.count) }
        startMonitor()
    }

    /// Number of corrections waiting to reach the cloud.
    var pendingCount: Int { queue.count }

    /// Record a batch of correction events. Persists to the local outbox
    /// immediately (offline-safe), then attempts a cloud flush. Never throws —
    /// failures stay queued and retry on reconnect / foreground.
    func record(_ events: [DamageFeedbackEvent]) async {
        guard !events.isEmpty else { return }
        queue.append(contentsOf: events)
        persistQueue()
        await flush()
    }

    /// Push everything queued to Supabase. Rows that land are removed from the
    /// outbox; the rest stay for the next attempt.
    func flush() async {
        guard !flushing, !queue.isEmpty else { return }
        guard CorrectionsSyncService.shared.syncEnabled else {
            status = .queued(count: queue.count)
            return
        }
        // Only attempt when signed in with a real Supabase user (the FK targets
        // auth.users). Dev-bypass ids keep the events safely queued.
        guard let userId = AuthStore.shared.currentUserId,
              UUID(uuidString: userId) != nil else {
            status = .queued(count: queue.count)
            return
        }

        flushing = true
        status = .saving
        defer { flushing = false }

        let batch = queue
        do {
            try await SupabaseService.client
                .from("damage_feedback")
                .upsert(batch, onConflict: "id")
                .execute()
            let sent = Set(batch.map(\.id))
            queue.removeAll { sent.contains($0.id) }
            persistQueue()
            status = queue.isEmpty ? .saved(at: Date()) : .queued(count: queue.count)
        } catch {
            print("[DamageFeedback] flush failed: \(error)")
            status = .queued(count: queue.count)
        }
    }

    /// Clear the outbox (e.g. explicit maintenance). Not wired to sign-out so
    /// unsynced corrections are preserved across sessions.
    func reset() {
        queue.removeAll()
        persistQueue()
        status = .idle
    }

    // MARK: - Connectivity

    private func startMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline { await self.flush() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "roofwise.damagefeedback.network"))
    }

    // MARK: - Persistence

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(filename)
    }

    private func loadQueue() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([DamageFeedbackEvent].self, from: data) else {
            return
        }
        queue = decoded
    }

    private func persistQueue() {
        guard let url = fileURL else { return }
        do {
            let data = try makeEncoder().encode(queue)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[DamageFeedback] persist failed: \(error)")
        }
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

    /// Best-effort 0–10 trust-score snapshot taken at correction time. Phase 3B's
    /// `UserTrustService` will replace this with the full Flywheel formula + a
    /// server-side recompute RPC; keeping it here means the editor has a single
    /// call site to repoint later.
    static func snapshotTrustScore() -> Double {
        let total = CorrectionsStore.shared.totalCount
        let volume = min(Double(total) / 50.0, 1.0)          // 0–1 over first 50 corrections
        let score = min(1.0 + volume * 2.0, 10.0)            // 1.0 baseline → up to 3.0
        return (score * 100).rounded() / 100
    }
}
