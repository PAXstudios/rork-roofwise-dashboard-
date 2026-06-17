import Foundation

// MARK: - RoofWise Decision Engine (Stage 6)
//
// The AI verdict layer. Takes the deterministic per-slope aggregation
// (Stage 4) + HAAG threshold verdicts (Stage 5) plus inspection-level inputs
// (brittleness, discontinuation, layers, storm history, carrier, policy) and
// asks RoofWise Vision's Decision Engine to produce a HAAG-grade roof
// recommendation, claim viability, insurance narrative, and homeowner summary.
//
// Missing inputs are passed as JSON null AND listed in `_data_not_captured`,
// so the engine surfaces them in `uncertainties[]` rather than fabricating
// defaults. The deterministic engine (DecisionEngine.swift) is unaffected.

// MARK: - Output models (decoded from the engine response)

nonisolated struct SlopeDecision: Codable, Sendable {
    var slope: String
    var hailHitsPerSquare: Int
    var windCreasedCount: Int
    var missingShingles: Int
    var brittlenessResult: String
    var collateralDamage: [String]
    var haagThresholdTriggered: Bool
    var recommendedAction: String
    var justification: String

    private enum CodingKeys: String, CodingKey {
        case slope
        case hailHitsPerSquare = "hail_hits_per_square"
        case windCreasedCount = "wind_creased_count"
        case missingShingles = "missing_shingles"
        case brittlenessResult = "brittleness_result"
        case collateralDamage = "collateral_damage"
        case haagThresholdTriggered = "haag_threshold_triggered"
        case recommendedAction = "recommended_action"
        case justification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slope = (try? c.decode(String.self, forKey: .slope)) ?? ""
        hailHitsPerSquare = (try? c.decode(Int.self, forKey: .hailHitsPerSquare)) ?? 0
        windCreasedCount = (try? c.decode(Int.self, forKey: .windCreasedCount)) ?? 0
        missingShingles = (try? c.decode(Int.self, forKey: .missingShingles)) ?? 0
        brittlenessResult = (try? c.decode(String.self, forKey: .brittlenessResult)) ?? "NOT_TESTED"
        collateralDamage = (try? c.decode([String].self, forKey: .collateralDamage)) ?? []
        haagThresholdTriggered = (try? c.decode(Bool.self, forKey: .haagThresholdTriggered)) ?? false
        recommendedAction = (try? c.decode(String.self, forKey: .recommendedAction)) ?? ""
        justification = (try? c.decode(String.self, forKey: .justification)) ?? ""
    }
}

nonisolated enum RoofRecommendation: String, Codable, Sendable {
    case fullReplacement = "FULL_REPLACEMENT"
    case partialReplacement = "PARTIAL_REPLACEMENT"
    case repair = "REPAIR"
    case noStormDamage = "NO_STORM_DAMAGE"
}

nonisolated enum ClaimViability: String, Codable, Sendable {
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

nonisolated enum SafetyRating: String, Codable, Sendable {
    case safe = "SAFE"
    case useCaution = "USE_CAUTION"
    case unsafe = "UNSAFE"
}

nonisolated struct RoofWiseDecisionEngineOutput: Codable, Sendable {
    var slopeDecisions: [SlopeDecision]
    var roofRecommendation: RoofRecommendation
    var claimViability: ClaimViability
    var roofSafetyRating: SafetyRating?
    var policyNotes: String
    var carrierSpecificRequirements: [String]
    var evidenceRequired: [String]
    var detailedExplanation: String
    var insuranceNarrative: String
    var homeownerSummary: String
    var haagThresholdsTriggered: [String]
    var uncertainties: [String]

    private enum CodingKeys: String, CodingKey {
        case slopeDecisions = "slope_decisions"
        case roofRecommendation = "roof_recommendation"
        case claimViability = "claim_viability"
        case roofSafetyRating = "roof_safety_rating"
        case policyNotes = "policy_notes"
        case carrierSpecificRequirements = "carrier_specific_requirements"
        case evidenceRequired = "evidence_required"
        case detailedExplanation = "detailed_explanation"
        case insuranceNarrative = "insurance_narrative"
        case homeownerSummary = "homeowner_summary"
        case haagThresholdsTriggered = "haag_thresholds_triggered"
        case uncertainties
    }

    /// Defensive decoding — the model can omit keys or use slightly different
    /// enum spellings; we fall back to safe defaults rather than throwing so a
    /// partial response still yields a usable verdict.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slopeDecisions = (try? c.decode([SlopeDecision].self, forKey: .slopeDecisions)) ?? []
        roofRecommendation = (try? c.decode(RoofRecommendation.self, forKey: .roofRecommendation)) ?? .repair
        claimViability = (try? c.decode(ClaimViability.self, forKey: .claimViability)) ?? .low
        roofSafetyRating = try? c.decode(SafetyRating.self, forKey: .roofSafetyRating)
        policyNotes = (try? c.decode(String.self, forKey: .policyNotes)) ?? ""
        carrierSpecificRequirements = (try? c.decode([String].self, forKey: .carrierSpecificRequirements)) ?? []
        evidenceRequired = (try? c.decode([String].self, forKey: .evidenceRequired)) ?? []
        detailedExplanation = (try? c.decode(String.self, forKey: .detailedExplanation)) ?? ""
        insuranceNarrative = (try? c.decode(String.self, forKey: .insuranceNarrative)) ?? ""
        homeownerSummary = (try? c.decode(String.self, forKey: .homeownerSummary)) ?? ""
        haagThresholdsTriggered = (try? c.decode([String].self, forKey: .haagThresholdsTriggered)) ?? []
        uncertainties = (try? c.decode([String].self, forKey: .uncertainties)) ?? []
    }
}

// MARK: - Inspection-level metadata (Stage 6 inputs)

/// The non-detection inputs the Decision Engine needs. Optionals model
/// "not captured yet" (Step 1.5c adds the wizard fields); they become JSON
/// null + a `_data_not_captured` entry rather than fabricated defaults.
struct InspectionMetadata {
    var roofAgeYears: Int? = nil
    var layers: Int? = nil
    var pitch: String? = nil
    var squareFootage: Double? = nil
    var brittleness: BrittlenessResult = .notTested
    var isDiscontinued: Bool = false
    var collateralChecklist: [String] = []
    var stormHistory: [StormEvent] = []
    var carrier: String? = nil
    var policyType: String? = nil   // "ACV" | "RCV"
    var deductible: Double? = nil
    var dayOfLoss: Date? = nil
    var customerNotes: String? = nil

    /// Builds Decision Engine metadata from an `Inspection`, mapping the
    /// Step 1.5c wizard fields. Anything the inspector skipped stays `nil` so
    /// `makeInputJSON` records it in `_data_not_captured` rather than guessing.
    static func from(_ insp: Inspection, stormHistory: [StormEvent] = []) -> InspectionMetadata {
        InspectionMetadata(
            roofAgeYears: insp.roof.estimatedAgeYears > 0 ? insp.roof.estimatedAgeYears : nil,
            layers: insp.roofLayers ?? (insp.roof.layers > 0 ? insp.roof.layers : nil),
            pitch: nil,
            squareFootage: insp.roof.detectedAreaSquares.map { $0 * 100 },
            brittleness: insp.brittlenessResult ?? .notTested,
            isDiscontinued: insp.materialDiscontinued ?? false,
            collateralChecklist: insp.collateral.observations,
            stormHistory: stormHistory,
            carrier: insp.job.carrierName.isEmpty ? nil : insp.job.carrierName,
            policyType: insp.policyType?.rawValue,
            deductible: insp.deductibleAmount.map { NSDecimalNumber(decimal: $0).doubleValue },
            dayOfLoss: insp.dayOfLoss,
            customerNotes: nil
        )
    }
}

/// Bundled output of the full Stage 4-6 pipeline for one inspection.
struct InspectionDecisionResult {
    let inspectionId: UUID
    let slopeData: [SlopeAggregateData]
    let slopeVerdicts: [HaagSlopeVerdict]
    let decision: RoofWiseDecisionEngineOutput
}

// MARK: - Service

@Observable
final class RoofWiseDecisionEngineService {
    static let shared = RoofWiseDecisionEngineService()

    /// The RoofWise Decision Engine system prompt. Compiled into the binary.
    private static let systemPrompt: String = """
    You are the RoofWise Decision Engine.
    Your output must ALWAYS be:
    1. Deterministic
    2. HAAG-aligned
    3. Based entirely on the structured JSON, photos, weather data, and user inputs
    4. Transparent — explain why you made each decision.

    Use HAAG Residential & Commercial Roofing Inspection Standards.
    Apply per-material thresholds: 3-tab >5 hits/100sf; architectural >8 hits/100sf; metal >25% panels dented OR seam disengagement; tile >10% broken; slate any visible damage; commercial flat >12 punctures/100sf OR adhesion failure.
    Mechanical/wear-and-tear must be ruled out. Thermal blisters and footfall damage are NOT storm damage. Collateral damage must corroborate the storm event within a 2-year max.

    Output ONE strict JSON object with EXACTLY these keys (no markdown, no preamble):
    {
      "slope_decisions": [
        {
          "slope": "Front",
          "hail_hits_per_square": number,
          "wind_creased_count": number,
          "missing_shingles": number,
          "brittleness_result": "PASS|FAIL|BORDERLINE|NOT_TESTED",
          "collateral_damage": [string],
          "haag_threshold_triggered": true|false,
          "recommended_action": "Full Replacement|Partial Replacement|Localized Repairs|No Storm-Related Work",
          "justification": string
        }
      ],
      "roof_recommendation": "FULL_REPLACEMENT|PARTIAL_REPLACEMENT|REPAIR|NO_STORM_DAMAGE",
      "claim_viability": "HIGH|MEDIUM|LOW",
      "roof_safety_rating": "SAFE|USE_CAUTION|UNSAFE",
      "policy_notes": string,
      "carrier_specific_requirements": [string],
      "evidence_required": [string],
      "detailed_explanation": string,
      "haag_thresholds_triggered": [string],
      "uncertainties": [string],
      "insurance_narrative": "Professional adjuster-language narrative referencing HAAG thresholds, storm correlation, collateral evidence, brittleness, repairability.",
      "homeowner_summary": "Plain-English summary the homeowner can understand."
    }

    If any input is missing (look at the input's "_data_not_captured" array and any null fields), explicitly state which data is missing and how it affects confidence in "uncertainties". Do NOT fabricate missing values.

    Output STRICT JSON only, no markdown, no preamble.
    """

    /// Runs the Decision Engine for one inspection's aggregated slopes.
    func evaluate(
        slopes: [SlopeAggregateData],
        slopeVerdicts: [HaagSlopeVerdict],
        roofAgeYears: Int?,
        layers: Int?,
        pitch: String?,
        squareFootage: Double?,
        brittleness: BrittlenessResult,
        isDiscontinued: Bool,
        collateralChecklist: [String],
        stormHistory: [StormEvent],
        carrier: String?,
        policyType: String?,
        deductible: Double?,
        dayOfLoss: Date?,
        customerNotes: String?
    ) async throws -> RoofWiseDecisionEngineOutput {
        let payload = Self.makeInputJSON(
            slopes: slopes,
            slopeVerdicts: slopeVerdicts,
            roofAgeYears: roofAgeYears,
            layers: layers,
            pitch: pitch,
            squareFootage: squareFootage,
            brittleness: brittleness,
            isDiscontinued: isDiscontinued,
            collateralChecklist: collateralChecklist,
            stormHistory: stormHistory,
            carrier: carrier,
            policyType: policyType,
            deductible: deductible,
            dayOfLoss: dayOfLoss,
            customerNotes: customerNotes
        )
        print("[RoofWiseEngine] ▶︎ evaluating \(slopes.count) slope(s); payload \(payload.count) bytes")
        let raw = try await GeminiAnalysisService().callRaw(systemPrompt: Self.systemPrompt, userJSON: payload)
        let output = try Self.parseDecisionEngineOutput(raw)
        print("[RoofWiseEngine] ✅ recommendation=\(output.roofRecommendation.rawValue) viability=\(output.claimViability.rawValue)")
        return output
    }

    // MARK: - Input assembly

    /// Builds a stable JSON document with every input as a top-level key.
    /// Missing optionals are emitted as JSON null and recorded in the
    /// `_data_not_captured` array so the engine surfaces them as uncertainties.
    nonisolated static func makeInputJSON(
        slopes: [SlopeAggregateData],
        slopeVerdicts: [HaagSlopeVerdict],
        roofAgeYears: Int?,
        layers: Int?,
        pitch: String?,
        squareFootage: Double?,
        brittleness: BrittlenessResult,
        isDiscontinued: Bool,
        collateralChecklist: [String],
        stormHistory: [StormEvent],
        carrier: String?,
        policyType: String?,
        deductible: Double?,
        dayOfLoss: Date?,
        customerNotes: String?
    ) -> String {
        let verdictById: [UUID: HaagSlopeVerdict] = Dictionary(
            slopeVerdicts.map { ($0.slopeId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let slopeInputs: [DecisionEngineInput.SlopeInput] = slopes.map { s in
            let v = verdictById[s.slopeId]
            return DecisionEngineInput.SlopeInput(
                slope: s.orientation,
                material: s.material.rawValue,
                area_squares: s.areaSquares,
                hail_hits_total: s.hailHitsTotal,
                hail_hits_per_100sqft: round1(s.hailHitsPerHundredSqFt),
                bruising_count: s.bruisingCount,
                mat_transfer_severity: s.matTransferSeverity.rawValue,
                granule_loss_level: s.granuleLossLevel.rawValue,
                wind_creased_count: s.windCreasedCount,
                wind_percent_damaged: round3(s.windPercentDamaged),
                missing_tabs_count: s.missingTabsCount,
                missing_shingles_count: s.missingShinglesCount,
                lifted_count: s.liftedCount,
                metal_dents_functional: s.metalDentsFunctionalCount,
                metal_dents_cosmetic: s.metalDentsCosmeticCount,
                metal_dented_panels_percent: round3(s.metalDentedPanelsPercent),
                seam_disengagement_count: s.seamDisengagementCount,
                tiles_broken_count: s.tilesBrokenCount,
                tiles_broken_percent: round3(s.tilesBrokenPercent),
                underlayment_exposure_count: s.underlaymentExposureCount,
                punctures_per_100sqft: round1(s.puncturesPerHundredSqFt),
                blisters_count: s.blistersCount,
                algae_moss_count: s.algaeMossCount,
                footfall_damage_count: s.footfallDamageCount,
                collateral_observations: s.collateralObservations,
                mean_detection_confidence: round1(s.meanDetectionConfidence),
                haag_verdict: v?.verdict.rawValue ?? "noDamage",
                haag_threshold_citation: v?.thresholdRuleCitation ?? HaagThresholds.rule(for: s.material),
                functional_damage_exceeds_threshold: v?.functionalDamageExceedsThreshold ?? false,
                verdict_reasoning: v?.verdictReasoning ?? "",
                storm_attributable: v?.stormAttributable ?? false,
                non_storm_damage_observed: v?.nonStormDamageObserved ?? []
            )
        }

        let storms: [DecisionEngineInput.StormInput] = stormHistory.map {
            DecisionEngineInput.StormInput(
                type: $0.type.rawValue,
                year: $0.year,
                date: $0.date,
                hail_size_inches: $0.sizeInches,
                wind_mph: $0.windMPH
            )
        }

        // Track which optional inputs were not captured.
        var notCaptured: [String] = []
        if roofAgeYears == nil { notCaptured.append("roof_age_years") }
        if layers == nil { notCaptured.append("layers") }
        if pitch == nil { notCaptured.append("pitch") }
        if squareFootage == nil { notCaptured.append("square_footage") }
        if brittleness == .notTested { notCaptured.append("brittleness_result (not tested)") }
        if carrier == nil { notCaptured.append("carrier") }
        if policyType == nil { notCaptured.append("policy_type (ACV/RCV)") }
        if deductible == nil { notCaptured.append("deductible") }
        if dayOfLoss == nil { notCaptured.append("day_of_loss") }
        if customerNotes == nil { notCaptured.append("customer_notes") }
        if storms.isEmpty { notCaptured.append("storm_history") }

        let dayOfLossString: String? = dayOfLoss.map { ISO8601DateFormatter().string(from: $0) }

        let input = DecisionEngineInput(
            slopes: slopeInputs,
            roof_age_years: roofAgeYears,
            layers: layers,
            pitch: pitch,
            square_footage: squareFootage,
            brittleness_result: brittleness.rawValue,
            material_discontinued: isDiscontinued,
            collateral_checklist: collateralChecklist,
            storm_history: storms,
            carrier: carrier,
            policy_type: policyType,
            deductible: deductible,
            day_of_loss: dayOfLossString,
            customer_notes: customerNotes,
            _data_not_captured: notCaptured
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(input),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Response parsing

    nonisolated static func parseDecisionEngineOutput(_ raw: String) throws -> RoofWiseDecisionEngineOutput {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Defensively isolate the outermost JSON object if the model added prose.
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8) else { throw LiveAnalyzeError.unparseable }
        return try JSONDecoder().decode(RoofWiseDecisionEngineOutput.self, from: data)
    }

    private nonisolated static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
    private nonisolated static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

// MARK: - Encodable input schema

/// The exact JSON shape posted to the Decision Engine. Encodable-only; keys are
/// snake_case to match the system prompt's expectations.
private struct DecisionEngineInput: Encodable {
    struct SlopeInput: Encodable {
        let slope: String
        let material: String
        let area_squares: Double
        let hail_hits_total: Int
        let hail_hits_per_100sqft: Double
        let bruising_count: Int
        let mat_transfer_severity: String
        let granule_loss_level: String
        let wind_creased_count: Int
        let wind_percent_damaged: Double
        let missing_tabs_count: Int
        let missing_shingles_count: Int
        let lifted_count: Int
        let metal_dents_functional: Int
        let metal_dents_cosmetic: Int
        let metal_dented_panels_percent: Double
        let seam_disengagement_count: Int
        let tiles_broken_count: Int
        let tiles_broken_percent: Double
        let underlayment_exposure_count: Int
        let punctures_per_100sqft: Double
        let blisters_count: Int
        let algae_moss_count: Int
        let footfall_damage_count: Int
        let collateral_observations: [String]
        let mean_detection_confidence: Double
        let haag_verdict: String
        let haag_threshold_citation: String
        let functional_damage_exceeds_threshold: Bool
        let verdict_reasoning: String
        let storm_attributable: Bool
        let non_storm_damage_observed: [String]
    }

    struct StormInput: Encodable {
        let type: String
        let year: Int
        let date: String
        let hail_size_inches: Double?
        let wind_mph: Int?
    }

    let slopes: [SlopeInput]
    let roof_age_years: Int?
    let layers: Int?
    let pitch: String?
    let square_footage: Double?
    let brittleness_result: String
    let material_discontinued: Bool
    let collateral_checklist: [String]
    let storm_history: [StormInput]
    let carrier: String?
    let policy_type: String?
    let deductible: Double?
    let day_of_loss: String?
    let customer_notes: String?
    let _data_not_captured: [String]
}
