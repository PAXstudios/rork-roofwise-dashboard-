import Foundation

// MARK: - Slope Aggregate Data (Stage 4)
//
// The deterministic shape produced by `SlopeAggregationService` from the
// per-photo `PhotoDetectionResult` outputs of a single slope. Stage 5 (HAAG
// thresholds) and Stage 6 (RoofWise Decision Engine) consume it.
//
// Pure data — `nonisolated` + `Sendable` so it can be built and decoded off the
// main actor.

nonisolated enum MatTransferSeverity: String, Codable, Sendable { case none, light, moderate, severe }
nonisolated enum GranuleLossLevel: String, Codable, Sendable { case none, light, moderate, severe }

nonisolated struct SlopeAggregateData: Codable, Sendable {
    var slopeId: UUID = UUID()
    var orientation: String = ""          // "N" | "NE" | "E" | ...
    var material: HaagRoofMaterial = .unknown
    var areaSquares: Double = 0           // 1 square = 100 sq ft

    // Asphalt-relevant
    var hailHitsTotal: Int = 0
    var hailHitsPerHundredSqFt: Double = 0
    var bruisingCount: Int = 0
    var matTransferSeverity: MatTransferSeverity = .none
    var granuleLossLevel: GranuleLossLevel = .none
    var windCreasedCount: Int = 0
    var windPercentDamaged: Double = 0    // (creased + missing tabs) / estimatedShingleCount
    var missingTabsCount: Int = 0
    var missingShinglesCount: Int = 0
    var liftedCount: Int = 0

    // Metal-specific
    var metalDentsFunctionalCount: Int = 0
    var metalDentsCosmeticCount: Int = 0
    var metalDentedPanelsPercent: Double = 0  // requires panel-count estimation from photos
    var seamDisengagementCount: Int = 0

    // Tile / slate-specific
    var tilesBrokenCount: Int = 0
    var tilesBrokenPercent: Double = 0
    var underlaymentExposureCount: Int = 0

    // Commercial flat
    var puncturesPerHundredSqFt: Double = 0
    var adhesionFailureAreaSqFt: Double = 0

    // Non-storm (must be ruled out)
    var blistersCount: Int = 0
    var algaeMossCount: Int = 0
    var footfallDamageCount: Int = 0

    // Collateral / non-storm observations harvested from forensic detections.
    var collateralObservations: [String] = []

    // Confidence aggregate
    var meanDetectionConfidence: Double = 0

    // Photo source tracking
    var photoIds: [UUID] = []
}

// MARK: - Per-slope HAAG verdict (Stage 5)

nonisolated enum SlopeVerdict: String, Codable, Sendable {
    case fullReplacement
    case partialReplacement
    case repair
    case noDamage

    var displayName: String {
        switch self {
        case .fullReplacement: return "Full Replacement"
        case .partialReplacement: return "Partial Replacement"
        case .repair: return "Repair"
        case .noDamage: return "No Damage"
        }
    }
}

nonisolated struct HaagSlopeVerdict: Codable, Sendable, Identifiable {
    var slopeId: UUID
    var hitsInTestSquare: Int          // for materials where hits matter
    var threshold: Int?                // applicable threshold; nil if rule isn't count-based
    var thresholdRuleCitation: String  // human-readable HAAG citation
    var functionalDamageExceedsThreshold: Bool
    var verdict: SlopeVerdict
    var verdictReasoning: String       // for the report
    var stormAttributable: Bool        // any storm-attributable detections present?
    var nonStormDamageObserved: [String] // wear, blistering, algae, etc.

    var id: UUID { slopeId }
}
