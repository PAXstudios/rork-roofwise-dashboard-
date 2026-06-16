import Foundation

// MARK: - Damage feedback (human-in-the-loop learning signal)
//
// One `DamageFeedbackEvent` maps 1:1 to a row in `public.damage_feedback`
// (Phase 1 schema). Every inspector edit on an AI detection — confirm, reject,
// modify, or add_new — produces exactly one event. These rows are the training
// signal for the recursive learning loop.
//
// The three pipeline-managed columns (`included_in_training`, `training_batch_id`,
// `validation_status`) are intentionally NOT modeled here so their DB defaults
// apply on insert.

/// Gemini-convention 2D detection box: `[ymin, xmin, ymax, xmax]` normalized to
/// 0–1000 (top-left origin, Y first). Matches the `box_2d` format emitted by
/// `GeminiAnalysisService` and stored in the `ai_bounding_box` /
/// `user_bounding_box` jsonb columns.
nonisolated struct FeedbackBox: Codable, Hashable, Sendable {
    let ymin: Double
    let xmin: Double
    let ymax: Double
    let xmax: Double

    /// Build from a normalized (0–1) marker center + radius. Each edge is
    /// clamped to [0,1] then scaled to the 0–1000 box_2d space.
    static func from(x: Double, y: Double, radius: Double) -> FeedbackBox {
        func n(_ v: Double) -> Double { (min(max(v, 0), 1) * 1000).rounded() }
        return FeedbackBox(ymin: n(y - radius), xmin: n(x - radius),
                           ymax: n(y + radius), xmax: n(x + radius))
    }
}

/// The four inspector actions captured per detection. Maps to the
/// `user_action` CHECK constraint on `damage_feedback`.
nonisolated enum DamageFeedbackAction: String, Codable, Hashable, Sendable {
    case confirm      // AI marker kept unchanged
    case reject       // AI marker deleted (false positive)
    case modify       // AI marker moved / resized / recategorized / re-severity
    case addNew = "add_new"  // inspector added a marker the AI missed
}

/// A single row in `public.damage_feedback`. Encoded directly for the Supabase
/// bulk upsert and for the on-disk offline outbox. `user_id` and the id columns
/// are sent as UUID strings (PostgREST casts text → uuid).
nonisolated struct DamageFeedbackEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let inspection_photo_id: String
    let user_id: String
    let ai_prediction_id: String?
    let ai_damage_type: String?
    let ai_bounding_box: FeedbackBox?
    let ai_confidence: Double?        // 0.00–9.99 (numeric(3,2)); store 0–1 model confidence
    let ai_model_version: String?
    let user_action: String
    let user_damage_type: String?
    let user_bounding_box: FeedbackBox?
    let user_severity: Int?           // 1–10
    let user_notes: String?
    let user_trust_score: Double?     // 0–10 (numeric(4,2)) snapshot at correction time
    let user_haag_certified: Bool
    let user_years_experience: Int?
    let created_at: Date

    init(id: String = UUID().uuidString,
         inspectionPhotoId: String,
         userId: String,
         action: DamageFeedbackAction,
         aiPredictionId: String? = nil,
         aiDamageType: String? = nil,
         aiBoundingBox: FeedbackBox? = nil,
         aiConfidence: Double? = nil,
         aiModelVersion: String? = nil,
         userDamageType: String? = nil,
         userBoundingBox: FeedbackBox? = nil,
         userSeverity: Int? = nil,
         userNotes: String? = nil,
         userTrustScore: Double? = nil,
         userHaagCertified: Bool = false,
         userYearsExperience: Int? = nil,
         createdAt: Date = .now) {
        self.id = id
        self.inspection_photo_id = inspectionPhotoId
        self.user_id = userId
        self.ai_prediction_id = aiPredictionId
        self.ai_damage_type = aiDamageType
        self.ai_bounding_box = aiBoundingBox
        self.ai_confidence = aiConfidence
        self.ai_model_version = aiModelVersion
        self.user_action = action.rawValue
        self.user_damage_type = userDamageType
        self.user_bounding_box = userBoundingBox
        self.user_severity = userSeverity
        self.user_notes = userNotes
        self.user_trust_score = userTrustScore
        self.user_haag_certified = userHaagCertified
        self.user_years_experience = userYearsExperience
        self.created_at = createdAt
    }
}
