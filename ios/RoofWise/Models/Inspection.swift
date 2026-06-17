import Foundation
import SwiftUI

// MARK: - Haag Inspection schema (single source of truth)
//
// Codable structs that match the Haag JSON schema EXACTLY.
// JSON uses snake_case; Swift uses camelCase via CodingKeys.

// MARK: Job

struct InspectionJob: Codable, Hashable {
    var reportId: String
    var inspectionDate: Date
    var reportDate: Date
    var inspectorName: String
    var companyName: String
    var clientName: String
    var propertyAddress: String
    var carrierName: String
    var policyNumber: String
    var claimNumber: String

    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case inspectionDate = "inspection_date"
        case reportDate = "report_date"
        case inspectorName = "inspector_name"
        case companyName = "company_name"
        case clientName = "client_name"
        case propertyAddress = "property_address"
        case carrierName = "carrier_name"
        case policyNumber = "policy_number"
        case claimNumber = "claim_number"
    }

    static func empty(reportId: String,
                      inspectorName: String,
                      companyName: String) -> InspectionJob {
        InspectionJob(
            reportId: reportId,
            inspectionDate: .now,
            reportDate: .now,
            inspectorName: inspectorName,
            companyName: companyName,
            clientName: "",
            propertyAddress: "",
            carrierName: "",
            policyNumber: "",
            claimNumber: ""
        )
    }
}

// MARK: Event

struct InspectionEvent: Codable, Hashable {
    var eventDate: Date?
    var hasHail: Bool
    var hasWind: Bool
    var hailMaxSizeIn: Double?
    var windMaxGustMph: Double?
    var weatherSources: [String]

    enum CodingKeys: String, CodingKey {
        case eventDate = "event_date"
        case hasHail = "has_hail"
        case hasWind = "has_wind"
        case hailMaxSizeIn = "hail_max_size_in"
        case windMaxGustMph = "wind_max_gust_mph"
        case weatherSources = "weather_sources"
    }

    static var empty: InspectionEvent {
        InspectionEvent(
            eventDate: nil,
            hasHail: false,
            hasWind: false,
            hailMaxSizeIn: nil,
            windMaxGustMph: nil,
            weatherSources: []
        )
    }
}

// MARK: Roof

enum RoofPrimaryMaterial: String, Codable, CaseIterable, Identifiable, Hashable {
    case asphaltShingle = "asphalt_shingle"
    case threeTabAsphalt = "three_tab_asphalt"
    case metalPanel = "metal_panel"
    case woodShake = "wood_shake"
    case concreteTile = "concrete_tile"
    case clayTile = "clay_tile"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asphaltShingle: return "Asphalt Shingle"
        case .threeTabAsphalt: return "3-Tab Asphalt"
        case .metalPanel: return "Metal Panel"
        case .woodShake: return "Wood Shake"
        case .concreteTile: return "Concrete Tile"
        case .clayTile: return "Clay Tile"
        }
    }
}

enum RoofGeometry: String, Codable, CaseIterable, Identifiable, Hashable {
    case gable, hip, mansard, flat, complex
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum RoofCondition: String, Codable, CaseIterable, Identifiable, Hashable {
    case excellent, good, fair, poor
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct InspectionRoof: Codable, Hashable {
    var primaryMaterial: RoofPrimaryMaterial
    var estimatedAgeYears: Int
    var layers: Int
    var geometry: RoofGeometry
    var overallConditionPreStorm: RoofCondition
    /// Total roof area (in roof squares) as detected by Google Solar / mock
    /// fallback. Distinct from inspector-entered slope areas so the Haag
    /// report can show both numbers side-by-side.
    var detectedAreaSquares: Double?

    enum CodingKeys: String, CodingKey {
        case primaryMaterial = "primary_material"
        case estimatedAgeYears = "estimated_age_years"
        case layers
        case geometry
        case overallConditionPreStorm = "overall_condition_pre_storm"
        case detectedAreaSquares = "detected_area_squares"
    }

    init(primaryMaterial: RoofPrimaryMaterial,
         estimatedAgeYears: Int,
         layers: Int,
         geometry: RoofGeometry,
         overallConditionPreStorm: RoofCondition,
         detectedAreaSquares: Double? = nil) {
        self.primaryMaterial = primaryMaterial
        self.estimatedAgeYears = estimatedAgeYears
        self.layers = layers
        self.geometry = geometry
        self.overallConditionPreStorm = overallConditionPreStorm
        self.detectedAreaSquares = detectedAreaSquares
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryMaterial = try c.decode(RoofPrimaryMaterial.self, forKey: .primaryMaterial)
        estimatedAgeYears = try c.decode(Int.self, forKey: .estimatedAgeYears)
        layers = try c.decode(Int.self, forKey: .layers)
        geometry = try c.decode(RoofGeometry.self, forKey: .geometry)
        overallConditionPreStorm = try c.decode(RoofCondition.self, forKey: .overallConditionPreStorm)
        detectedAreaSquares = try c.decodeIfPresent(Double.self, forKey: .detectedAreaSquares)
    }

    static var empty: InspectionRoof {
        InspectionRoof(
            primaryMaterial: .asphaltShingle,
            estimatedAgeYears: 10,
            layers: 1,
            geometry: .gable,
            overallConditionPreStorm: .good
        )
    }
}

// MARK: Slope

struct SlopeHailDamage: Codable, Hashable {
    var asphaltBruise: Int
    var asphaltMatFracture: Int
    var asphaltGranuleLossExposed: Int

    enum CodingKeys: String, CodingKey {
        case asphaltBruise = "asphalt_bruise"
        case asphaltMatFracture = "asphalt_mat_fracture"
        case asphaltGranuleLossExposed = "asphalt_granule_loss_exposed"
    }

    static var empty: SlopeHailDamage {
        SlopeHailDamage(asphaltBruise: 0, asphaltMatFracture: 0, asphaltGranuleLossExposed: 0)
    }
}

struct SlopeWindDamage: Codable, Hashable {
    var shingleCrease: Int
    var shingleMissing: Int
    var shingleLiftedUnsealed: Int

    enum CodingKeys: String, CodingKey {
        case shingleCrease = "shingle_crease"
        case shingleMissing = "shingle_missing"
        case shingleLiftedUnsealed = "shingle_lifted_unsealed"
    }

    static var empty: SlopeWindDamage {
        SlopeWindDamage(shingleCrease: 0, shingleMissing: 0, shingleLiftedUnsealed: 0)
    }
}

struct SlopeWearDamage: Codable, Hashable {
    var naturalWeathering: Bool
    var footTraffic: Bool
    var manufacturingDefect: Bool

    enum CodingKeys: String, CodingKey {
        case naturalWeathering = "natural_weathering"
        case footTraffic = "foot_traffic"
        case manufacturingDefect = "manufacturing_defect"
    }

    static var empty: SlopeWearDamage {
        SlopeWearDamage(naturalWeathering: false, footTraffic: false, manufacturingDefect: false)
    }
}

struct SlopeDamageTypes: Codable, Hashable {
    var hail: SlopeHailDamage
    var wind: SlopeWindDamage
    var wear: SlopeWearDamage

    static var empty: SlopeDamageTypes {
        SlopeDamageTypes(hail: .empty, wind: .empty, wear: .empty)
    }
}

struct Slope: Codable, Hashable, Identifiable {
    var orientation: String
    var pitchRiseOver12: Int
    var areaSquares: Double
    var testSquareCount: Int
    var damagedUnitsPerSquare: Int
    var unitRepairCost: Double
    var repairDifficultyFactor: Double
    var repairCostSlope: Double
    var replacementCostSlope: Double
    var functionalDamagePresent: Bool
    var cosmeticOnly: Bool
    var slopeReplacementRecommended: Bool
    var slopeRepairsRecommended: Bool
    var damageTypes: SlopeDamageTypes
    /// Per-slope detected area (squares) from Google Solar segments. Survives
    /// inspector edits to areaSquares so the report can show both.
    var detectedAreaSquares: Double?
    /// Phase 8 (flag-gated). Set by `DecisionEngine` when mean per-slope AI
    /// confidence is below 50. Surfaces a “Verify with inspector” chip in the
    /// slope verdict UI. Recomputed on every `DecisionEngine.decide` and never
    /// encoded — transient runtime state only.
    var verifyWithInspector: Bool = false
    /// Phase 9 transient. Per-slope AI findings, written by InspectionStore
    /// after each successful analyze run. Never encoded. Drives the Phase 8
    /// confidence chips in SlopeCaptureView and the Phase 8/9 Verify badge.
    var aiFindings: [InspectionFinding] = []

    enum CodingKeys: String, CodingKey {
        case orientation
        case pitchRiseOver12 = "pitch_rise_over_12"
        case areaSquares = "area_squares"
        case testSquareCount = "test_square_count"
        case damagedUnitsPerSquare = "damaged_units_per_square"
        case unitRepairCost = "unit_repair_cost"
        case repairDifficultyFactor = "repair_difficulty_factor"
        case repairCostSlope = "repair_cost_slope"
        case replacementCostSlope = "replacement_cost_slope"
        case functionalDamagePresent = "functional_damage_present"
        case cosmeticOnly = "cosmetic_only"
        case slopeReplacementRecommended = "slope_replacement_recommended"
        case slopeRepairsRecommended = "slope_repairs_recommended"
        case damageTypes = "damage_types"
        case detectedAreaSquares = "detected_area_squares"
        // verifyWithInspector is intentionally not encoded — recomputed at runtime.
    }

    init(orientation: String,
         pitchRiseOver12: Int,
         areaSquares: Double,
         testSquareCount: Int,
         damagedUnitsPerSquare: Int,
         unitRepairCost: Double,
         repairDifficultyFactor: Double,
         repairCostSlope: Double,
         replacementCostSlope: Double,
         functionalDamagePresent: Bool,
         cosmeticOnly: Bool,
         slopeReplacementRecommended: Bool,
         slopeRepairsRecommended: Bool,
         damageTypes: SlopeDamageTypes,
         detectedAreaSquares: Double? = nil) {
        self.orientation = orientation
        self.pitchRiseOver12 = pitchRiseOver12
        self.areaSquares = areaSquares
        self.testSquareCount = testSquareCount
        self.damagedUnitsPerSquare = damagedUnitsPerSquare
        self.unitRepairCost = unitRepairCost
        self.repairDifficultyFactor = repairDifficultyFactor
        self.repairCostSlope = repairCostSlope
        self.replacementCostSlope = replacementCostSlope
        self.functionalDamagePresent = functionalDamagePresent
        self.cosmeticOnly = cosmeticOnly
        self.slopeReplacementRecommended = slopeReplacementRecommended
        self.slopeRepairsRecommended = slopeRepairsRecommended
        self.damageTypes = damageTypes
        self.detectedAreaSquares = detectedAreaSquares
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orientation = try c.decode(String.self, forKey: .orientation)
        pitchRiseOver12 = try c.decode(Int.self, forKey: .pitchRiseOver12)
        areaSquares = try c.decode(Double.self, forKey: .areaSquares)
        testSquareCount = try c.decode(Int.self, forKey: .testSquareCount)
        damagedUnitsPerSquare = try c.decode(Int.self, forKey: .damagedUnitsPerSquare)
        unitRepairCost = try c.decode(Double.self, forKey: .unitRepairCost)
        repairDifficultyFactor = try c.decode(Double.self, forKey: .repairDifficultyFactor)
        repairCostSlope = try c.decode(Double.self, forKey: .repairCostSlope)
        replacementCostSlope = try c.decode(Double.self, forKey: .replacementCostSlope)
        functionalDamagePresent = try c.decode(Bool.self, forKey: .functionalDamagePresent)
        cosmeticOnly = try c.decode(Bool.self, forKey: .cosmeticOnly)
        slopeReplacementRecommended = try c.decode(Bool.self, forKey: .slopeReplacementRecommended)
        slopeRepairsRecommended = try c.decode(Bool.self, forKey: .slopeRepairsRecommended)
        damageTypes = try c.decode(SlopeDamageTypes.self, forKey: .damageTypes)
        detectedAreaSquares = try c.decodeIfPresent(Double.self, forKey: .detectedAreaSquares)
    }

    var id: String { orientation }
}

// MARK: Collateral

struct InspectionCollateral: Codable, Hashable {
    var gutterDents: Bool
    var downspoutDents: Bool
    var screenDamage: Bool
    var sidingImpacts: Bool
    var vehicleDamageReported: Bool

    enum CodingKeys: String, CodingKey {
        case gutterDents = "gutter_dents"
        case downspoutDents = "downspout_dents"
        case screenDamage = "screen_damage"
        case sidingImpacts = "siding_impacts"
        case vehicleDamageReported = "vehicle_damage_reported"
    }

    static var empty: InspectionCollateral {
        InspectionCollateral(
            gutterDents: false,
            downspoutDents: false,
            screenDamage: false,
            sidingImpacts: false,
            vehicleDamageReported: false
        )
    }

    /// Human-readable list of present collateral observations, used as the
    /// Decision Engine's `collateral_checklist` corroborating-evidence input.
    var observations: [String] {
        var out: [String] = []
        if gutterDents { out.append("Gutter dents present") }
        if downspoutDents { out.append("Downspout dents present") }
        if screenDamage { out.append("Window/screen damage present") }
        if sidingImpacts { out.append("Siding impact marks present") }
        if vehicleDamageReported { out.append("Vehicle hail damage reported") }
        return out
    }
}

// MARK: Summary

struct InspectionSummary: Codable, Hashable {
    var roofAnyFunctionalDamage: Bool
    var roofFullReplacementRecommended: Bool
    var roofPartialReplacementRecommended: Bool
    var roofRepairsRecommended: Bool
    var replacementSlopesList: String
    var notes: String

    enum CodingKeys: String, CodingKey {
        case roofAnyFunctionalDamage = "roof_any_functional_damage"
        case roofFullReplacementRecommended = "roof_full_replacement_recommended"
        case roofPartialReplacementRecommended = "roof_partial_replacement_recommended"
        case roofRepairsRecommended = "roof_repairs_recommended"
        case replacementSlopesList = "replacement_slopes_list"
        case notes
    }

    static var empty: InspectionSummary {
        InspectionSummary(
            roofAnyFunctionalDamage: false,
            roofFullReplacementRecommended: false,
            roofPartialReplacementRecommended: false,
            roofRepairsRecommended: false,
            replacementSlopesList: "",
            notes: ""
        )
    }
}

// MARK: Inspection root

struct Inspection: Codable, Hashable, Identifiable {
    var job: InspectionJob
    var event: InspectionEvent
    var roof: InspectionRoof
    var slopes: [Slope]
    var collateral: InspectionCollateral
    var summary: InspectionSummary
    /// Optional PencilKit-captured signatures, persisted as PNG bytes.
    var inspectorSignaturePng: Data?
    var homeownerSignaturePng: Data?
    /// If this job was created via the Cost Estimator's Convert-to-Job CTA,
    /// holds the id of the originating `SavedEstimate` so JobDetailView can
    /// surface a "From estimate" chip and re-open it at Step 4.
    var originEstimateId: UUID?

    // MARK: Decision Engine inputs (added Step 1.5c)
    // All optional so inspections saved before this step decode unchanged
    // (decodeIfPresent → nil). Each maps to a RoofWise Decision Engine input.
    /// Result of the field brittleness test (bend a tab 90°).
    var brittlenessResult: BrittlenessResult?
    /// Whether the roof's material is discontinued (forces full replacement).
    var materialDiscontinued: Bool?
    /// Free-text reason / manufacturer notes when `materialDiscontinued == true`.
    var materialDiscontinuedReason: String?
    /// Number of roofing layers (1, 2, 3, or 4 meaning 4+). Distinct from the
    /// pre-storm baseline `roof.layers`; this is the inspector-confirmed count.
    var roofLayers: Int?
    /// Insurance valuation basis (ACV vs RCV).
    var policyType: PolicyType?
    /// Policy deductible amount in dollars.
    var deductibleAmount: Decimal?
    /// Homeowner-reported storm date ("Day of Loss").
    var dayOfLoss: Date?

    enum CodingKeys: String, CodingKey {
        case job, event, roof, slopes, collateral, summary
        case inspectorSignaturePng = "inspector_signature_png"
        case homeownerSignaturePng = "homeowner_signature_png"
        case originEstimateId = "origin_estimate_id"
        case brittlenessResult = "brittleness_result"
        case materialDiscontinued = "material_discontinued"
        case materialDiscontinuedReason = "material_discontinued_reason"
        case roofLayers = "roof_layers"
        case policyType = "policy_type"
        case deductibleAmount = "deductible_amount"
        case dayOfLoss = "day_of_loss"
    }

    /// Stable identity backed by `report_id`.
    var id: String { job.reportId }

    init(job: InspectionJob,
         event: InspectionEvent,
         roof: InspectionRoof,
         slopes: [Slope],
         collateral: InspectionCollateral,
         summary: InspectionSummary,
         inspectorSignaturePng: Data? = nil,
         homeownerSignaturePng: Data? = nil,
         originEstimateId: UUID? = nil,
         brittlenessResult: BrittlenessResult? = nil,
         materialDiscontinued: Bool? = nil,
         materialDiscontinuedReason: String? = nil,
         roofLayers: Int? = nil,
         policyType: PolicyType? = nil,
         deductibleAmount: Decimal? = nil,
         dayOfLoss: Date? = nil) {
        self.job = job
        self.event = event
        self.roof = roof
        self.slopes = slopes
        self.collateral = collateral
        self.summary = summary
        self.inspectorSignaturePng = inspectorSignaturePng
        self.homeownerSignaturePng = homeownerSignaturePng
        self.originEstimateId = originEstimateId
        self.brittlenessResult = brittlenessResult
        self.materialDiscontinued = materialDiscontinued
        self.materialDiscontinuedReason = materialDiscontinuedReason
        self.roofLayers = roofLayers
        self.policyType = policyType
        self.deductibleAmount = deductibleAmount
        self.dayOfLoss = dayOfLoss
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        job = try c.decode(InspectionJob.self, forKey: .job)
        event = try c.decode(InspectionEvent.self, forKey: .event)
        roof = try c.decode(InspectionRoof.self, forKey: .roof)
        slopes = try c.decode([Slope].self, forKey: .slopes)
        collateral = try c.decode(InspectionCollateral.self, forKey: .collateral)
        summary = try c.decode(InspectionSummary.self, forKey: .summary)
        inspectorSignaturePng = try c.decodeIfPresent(Data.self, forKey: .inspectorSignaturePng)
        homeownerSignaturePng = try c.decodeIfPresent(Data.self, forKey: .homeownerSignaturePng)
        originEstimateId = try c.decodeIfPresent(UUID.self, forKey: .originEstimateId)
        brittlenessResult = try c.decodeIfPresent(BrittlenessResult.self, forKey: .brittlenessResult)
        materialDiscontinued = try c.decodeIfPresent(Bool.self, forKey: .materialDiscontinued)
        materialDiscontinuedReason = try c.decodeIfPresent(String.self, forKey: .materialDiscontinuedReason)
        roofLayers = try c.decodeIfPresent(Int.self, forKey: .roofLayers)
        policyType = try c.decodeIfPresent(PolicyType.self, forKey: .policyType)
        deductibleAmount = try c.decodeIfPresent(Decimal.self, forKey: .deductibleAmount)
        dayOfLoss = try c.decodeIfPresent(Date.self, forKey: .dayOfLoss)
    }
}

// MARK: - Decision Engine inputs (Step 1.5c)

/// Insurance policy valuation basis. `nil` on `Inspection` means "not
/// captured" — the Decision Engine treats it as missing rather than a default.
nonisolated enum PolicyType: String, Codable, Sendable, CaseIterable {
    case acv = "ACV"
    case rcv = "RCV"

    var displayName: String { rawValue }
}

// MARK: Stub user

struct InspectorUser: Hashable, Sendable {
    var name: String
    var company: String

    static let current = InspectorUser(
        name: "Alex Coleman",
        company: "RoofWise Inspection Services"
    )
}
