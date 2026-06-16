import Foundation
import Observation
import Supabase

/// Pushes the recursive-learning signal to Supabase. On every inspector
/// `Correction` it writes one or more `damage_feedback` rows (the per-marker
/// before/after the inspector changed) and upserts the inspector's
/// `user_trust_profile` row. Fire-and-forget: failures are logged and surfaced
/// via `status`, never thrown to the UI. Local JSONL outbox
/// (`CorrectionsSyncService`) remains the offline-safe record of truth.
@Observable
@MainActor
final class FeedbackSyncService {
    static let shared = FeedbackSyncService()

    enum Status: Equatable {
        case idle
        case syncing
        case synced(at: Date)
        case failed(message: String)
    }

    private(set) var status: Status = .idle

    private init() {}

    /// Fire-and-forget entry point called from `CorrectionsStore.append`.
    /// Respects the same Settings toggle as the local outbox.
    func enqueue(_ correction: Correction) {
        guard CorrectionsSyncService.shared.syncEnabled else { return }
        Task { await sync(correction) }
    }

    /// Insert the `damage_feedback` rows for one correction and refresh the
    /// trust profile. Skips silently when the user isn't signed in with a real
    /// Supabase id (e.g. dev bypass user).
    func sync(_ correction: Correction) async {
        guard let rawId = AuthStore.shared.currentUserId,
              UUID(uuidString: rawId) != nil else {
            // Not a real Supabase user — outbox still captured it locally.
            return
        }

        status = .syncing
        do {
            let trustScore = Self.computeTrustScore()
            let rows = Self.feedbackRows(from: correction, userId: rawId, trustScore: trustScore)
            if !rows.isEmpty {
                try await SupabaseService.client
                    .from("damage_feedback")
                    .insert(rows)
                    .execute()
            }

            let profile = Self.trustProfileRow(userId: rawId, trustScore: trustScore)
            try await SupabaseService.client
                .from("user_trust_profile")
                .upsert(profile, onConflict: "user_id")
                .execute()

            status = .synced(at: Date())
        } catch {
            print("[FeedbackSync] failed: \(error)")
            status = .failed(message: Self.friendlyMessage(for: error))
        }
    }

    // MARK: - Row builders

    /// Map a `Correction` into per-marker `damage_feedback` rows. Edits emit one
    /// row per delta op (added/deleted/moved/resized/recategorized); whole-photo
    /// confirm/reject emits one row per original marker (or a single summary row
    /// when the snapshot has no markers).
    private static func feedbackRows(from c: Correction,
                                     userId: String,
                                     trustScore: Double) -> [RemoteFeedback] {
        let original = CorrectionsStore.decodeSnapshot(c.originalDetection)
        let delta = CorrectionsStore.decodeDelta(c.delta)
        let now = c.correctedAt
        var rows: [RemoteFeedback] = []

        if let delta, !delta.ops.isEmpty {
            for op in delta.ops {
                let origMarker = original?.markers.first { $0.id == op.markerId }
                let action: String
                switch op.kind {
                case .added: action = "add_new"
                case .deleted: action = "reject"
                case .moved, .resized, .recategorized: action = "modify"
                }

                let correctedType = op.category ?? origMarker?.category
                let correctedBox: BoundingBox? = {
                    if let x = op.x, let y = op.y {
                        return BoundingBox.from(x: x, y: y, radius: op.radius ?? origMarker?.radius ?? 0.04)
                    }
                    return origMarker.map { BoundingBox.from(x: $0.x, y: $0.y, radius: $0.radius) }
                }()

                rows.append(RemoteFeedback(
                    user_id: userId,
                    original_damage_type: origMarker?.category,
                    original_bounding_box: origMarker.map { BoundingBox.from(x: $0.x, y: $0.y, radius: $0.radius) },
                    original_severity: severityScale(origMarker?.severity),
                    user_action: action,
                    corrected_damage_type: correctedType,
                    corrected_bounding_box: correctedBox,
                    severity: severityScale(op.severity) ?? severityScale(origMarker?.severity),
                    user_trust_score: trustScore,
                    created_at: now
                ))
            }
        } else if let markers = original?.markers, !markers.isEmpty {
            let action = actionFor(c.correctionType)
            for m in markers {
                let box = BoundingBox.from(x: m.x, y: m.y, radius: m.radius)
                rows.append(RemoteFeedback(
                    user_id: userId,
                    original_damage_type: m.category,
                    original_bounding_box: box,
                    original_severity: severityScale(m.severity),
                    user_action: action,
                    corrected_damage_type: m.category,
                    corrected_bounding_box: box,
                    severity: severityScale(m.severity),
                    user_trust_score: trustScore,
                    created_at: now
                ))
            }
        } else {
            rows.append(RemoteFeedback(
                user_id: userId,
                original_damage_type: c.categoriesAffected.first,
                original_bounding_box: nil,
                original_severity: nil,
                user_action: actionFor(c.correctionType),
                corrected_damage_type: c.categoriesAffected.first,
                corrected_bounding_box: nil,
                severity: nil,
                user_trust_score: trustScore,
                created_at: now
            ))
        }

        return rows
    }

    private static func trustProfileRow(userId: String, trustScore: Double) -> RemoteTrustProfile {
        let store = CorrectionsStore.shared
        let total = store.totalCount
        let validated = store.items.filter { $0.correctionType == .confirmed }.count
        let agreement = total > 0 ? Double(validated) / Double(total) : 0
        return RemoteTrustProfile(
            user_id: userId,
            total_corrections: total,
            validated_corrections: validated,
            agreement_rate: (agreement * 10000).rounded() / 10000,
            current_trust_score: (trustScore * 100).rounded() / 100,
            updated_at: Date()
        )
    }

    /// Trust score 0-100: base 50 + agreement weight + a small volume bonus.
    private static func computeTrustScore() -> Double {
        let store = CorrectionsStore.shared
        let total = store.totalCount
        let validated = store.items.filter { $0.correctionType == .confirmed }.count
        let agreement = total > 0 ? Double(validated) / Double(total) : 0
        let volumeBonus = min(Double(total) / 50.0, 1.0) * 10.0
        let score = 50.0 + agreement * 40.0 + volumeBonus
        return min(max(score, 0), 100)
    }

    private static func actionFor(_ type: CorrectionType) -> String {
        switch type {
        case .confirmed: return "confirm"
        case .rejected, .removedFalsePositive: return "reject"
        case .addedMissed: return "add_new"
        case .edited: return "modify"
        }
    }

    /// Map the app's category severity ("Minor"/"Moderate"/"Severe") onto the
    /// 1-10 scale stored in `damage_feedback.severity`.
    private static func severityScale(_ raw: String?) -> Int? {
        switch raw?.lowercased() {
        case "minor": return 3
        case "moderate": return 6
        case "severe": return 9
        default: return nil
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("network") || raw.contains("offline") || raw.contains("internet") {
            return "Offline — feedback will sync when you're back online."
        }
        if raw.contains("jwt") || raw.contains("not authenticated") {
            return "Session expired — please sign in again."
        }
        if raw.contains("does not exist") || raw.contains("relation") {
            return "Learning tables not set up yet — run the schema SQL in Supabase."
        }
        return "Feedback sync failed: \(error.localizedDescription)"
    }
}

// MARK: - Remote row DTOs

/// Gemini-convention bounding box: `[ymin, xmin, ymax, xmax]` normalized 0-1000.
nonisolated struct BoundingBox: Codable, Sendable {
    let ymin: Double
    let xmin: Double
    let ymax: Double
    let xmax: Double

    /// Build from a normalized (0-1) center + radius marker.
    static func from(x: Double, y: Double, radius: Double) -> BoundingBox {
        func clamp(_ v: Double) -> Double { min(max(v * 1000.0, 0), 1000) }
        return BoundingBox(
            ymin: clamp(y - radius),
            xmin: clamp(x - radius),
            ymax: clamp(y + radius),
            xmax: clamp(x + radius)
        )
    }
}

/// Row for `public.damage_feedback`. Optional columns are omitted when nil so
/// DB defaults (`included_in_training`, `validation_status`) apply on insert.
nonisolated struct RemoteFeedback: Codable, Sendable {
    let user_id: String
    let original_damage_type: String?
    let original_bounding_box: BoundingBox?
    let original_severity: Int?
    let user_action: String
    let corrected_damage_type: String?
    let corrected_bounding_box: BoundingBox?
    let severity: Int?
    let user_trust_score: Double?
    let created_at: Date
}

/// Row for `public.user_trust_profile`. `haag_certified` and `years_experience`
/// are intentionally omitted so existing/default values are preserved on upsert.
nonisolated struct RemoteTrustProfile: Codable, Sendable {
    let user_id: String
    let total_corrections: Int
    let validated_corrections: Int
    let agreement_rate: Double
    let current_trust_score: Double
    let updated_at: Date
}
