import Foundation

// MARK: - HAAG Roof Material (detection-pipeline taxonomy)
//
// This is the material taxonomy used by the per-photo detection pipeline and
// the per-slope aggregation layer. It is intentionally finer-grained than the
// legacy `HaagRoofCovering` (in HaagDecisionEngine.swift), which models the
// deterministic rules engine. The two coexist: the pipeline classifies into
// `HaagRoofMaterial`, aggregation maps to the right threshold here, and the
// Decision Engine produces the final HAAG verdict.

nonisolated enum HaagRoofMaterial: String, CaseIterable, Codable, Sendable {
    case threeTabAsphalt = "3_tab_asphalt"
    case architecturalAsphalt = "architectural_asphalt" // includes laminated
    case woodShake = "wood_shake"
    case woodShingle = "wood_shingle"
    case metalPanel = "metal_panel"
    case stoneCoatedMetal = "stone_coated_metal"
    case clayTile = "clay_tile"
    case concreteTile = "concrete_tile"
    case slate = "slate"
    case syntheticSlate = "synthetic_slate"
    case syntheticShake = "synthetic_shake"
    case tpo = "tpo"
    case epdm = "epdm"
    case pvc = "pvc"
    case modifiedBitumen = "modified_bitumen"
    case unknown = "unknown"

    var category: MaterialCategory {
        switch self {
        case .threeTabAsphalt: return .threeTab
        case .architecturalAsphalt: return .laminate
        case .woodShake, .woodShingle: return .wood
        case .metalPanel, .stoneCoatedMetal: return .metal
        case .clayTile, .concreteTile: return .tile
        case .slate, .syntheticSlate: return .slate
        case .syntheticShake: return .wood
        case .tpo, .epdm, .pvc, .modifiedBitumen: return .commercialFlat
        case .unknown: return .unknown
        }
    }

    enum MaterialCategory: String, Codable, Sendable {
        case threeTab, laminate, wood, metal, tile, slate, commercialFlat, unknown
    }

    /// Human-friendly label for UI.
    var displayName: String {
        switch self {
        case .threeTabAsphalt: return "3-Tab Asphalt"
        case .architecturalAsphalt: return "Architectural Asphalt"
        case .woodShake: return "Wood Shake"
        case .woodShingle: return "Wood Shingle"
        case .metalPanel: return "Metal Panel"
        case .stoneCoatedMetal: return "Stone-Coated Metal"
        case .clayTile: return "Clay Tile"
        case .concreteTile: return "Concrete Tile"
        case .slate: return "Slate"
        case .syntheticSlate: return "Synthetic Slate"
        case .syntheticShake: return "Synthetic Shake"
        case .tpo: return "TPO Membrane"
        case .epdm: return "EPDM Membrane"
        case .pvc: return "PVC Membrane"
        case .modifiedBitumen: return "Modified Bitumen"
        case .unknown: return "Unknown"
        }
    }

    /// Best-effort mapping from a free-text classifier label (e.g. Gemini's
    /// `shingle_type`) to a `HaagRoofMaterial` case.
    static func from(label: String?) -> HaagRoofMaterial {
        guard let raw = label?.lowercased() else { return .unknown }
        if raw.contains("3-tab") || raw.contains("3 tab") || raw.contains("three tab") { return .threeTabAsphalt }
        if raw.contains("architectural") || raw.contains("laminate") || raw.contains("dimensional") || raw.contains("luxury asphalt") { return .architecturalAsphalt }
        if raw.contains("stone") && raw.contains("metal") { return .stoneCoatedMetal }
        if raw.contains("metal") || raw.contains("standing seam") || raw.contains("steel") || raw.contains("aluminum") { return .metalPanel }
        if raw.contains("clay") || raw.contains("spanish") || raw.contains("barrel") { return .clayTile }
        if raw.contains("concrete tile") { return .concreteTile }
        if raw.contains("synthetic slate") { return .syntheticSlate }
        if raw.contains("slate") { return .slate }
        if raw.contains("synthetic shake") || raw.contains("composite shake") { return .syntheticShake }
        if raw.contains("shake") || raw.contains("cedar") { return .woodShake }
        if raw.contains("wood") { return .woodShingle }
        if raw.contains("tpo") { return .tpo }
        if raw.contains("epdm") { return .epdm }
        if raw.contains("pvc") { return .pvc }
        if raw.contains("modified bitumen") || raw.contains("mod-bit") || raw.contains("bur") || raw.contains("built-up") { return .modifiedBitumen }
        if raw.contains("asphalt") || raw.contains("composition") || raw.contains("shingle") { return .architecturalAsphalt }
        return .unknown
    }
}

// MARK: - Brittleness test result

nonisolated enum BrittlenessResult: String, Codable, Sendable, CaseIterable {
    case pass
    case borderline
    case fail
    case notTested

    var displayName: String {
        switch self {
        case .pass: return "Pass"
        case .borderline: return "Borderline"
        case .fail: return "Fail"
        case .notTested: return "Not Tested"
        }
    }
}

// MARK: - HAAG Thresholds

/// HAAG-aligned thresholds per the RoofWise Decision Engine framework.
/// All values are deterministic and citable in the report.
nonisolated enum HaagThresholds {

    /// For asphalt: hail hits per 100 sq ft test square that triggers replacement.
    static func asphaltHailHitsThreshold(_ material: HaagRoofMaterial) -> Int {
        switch material {
        case .threeTabAsphalt: return 5      // > 5 hits per 100 sq ft
        case .architecturalAsphalt: return 8 // > 8 hits per 100 sq ft
        default: return 0
        }
    }

    /// For asphalt: number of wind-creased shingles on a slope that triggers replacement.
    static func asphaltCreasedShinglesThreshold(_ material: HaagRoofMaterial) -> Int {
        switch material {
        case .threeTabAsphalt, .architecturalAsphalt: return 3
        default: return 0
        }
    }

    /// For asphalt laminate: percent of wind-damaged shingles on a slope.
    static let laminateWindDamagePercentThreshold: Double = 0.05 // 5%

    /// For metal panel: percent of panels with functional dents that triggers replacement.
    static let metalDentedPanelPercentThreshold: Double = 0.25 // 25%

    /// For tile (clay or concrete): percent broken tiles that triggers replacement.
    static let tileBrokenPercentThreshold: Double = 0.10 // 10%

    /// For clay tile specifically: a single visibly broken tile qualifies for
    /// replacement of that tile.
    static let clayTilePerTileReplacement: Bool = true

    /// For commercial flat: punctures per 100 sq ft test square that triggers replacement.
    static let commercialFlatPunctureDensityThreshold: Int = 12 // > 12 per 100 sq ft

    /// For wood shake: hits per 100 sq ft that triggers replacement.
    static let woodShakeHitsThreshold: Int = 5

    /// For wood shake: number of broken shakes that triggers replacement.
    static let woodShakeBrokenThreshold: Int = 3

    /// Human-readable HAAG rule citation for the report.
    static func rule(for material: HaagRoofMaterial) -> String {
        switch material {
        case .threeTabAsphalt:
            return "HAAG: > 5 hail hits per 100 sq ft test square OR ≥ 3 creased courses → replacement. Discontinued material → replacement."
        case .architecturalAsphalt:
            return "HAAG: > 8 hail hits per 100 sq ft test square OR > 5% wind-damaged shingles on slope OR ≥ 3 creased courses → replacement. Discontinued material → replacement."
        case .metalPanel:
            return "HAAG: > 25% panels with functional dents OR seam disengagement → replacement. Cosmetic dents noted only."
        case .stoneCoatedMetal:
            return "HAAG: > 25% panels with functional dents OR seam disengagement OR significant granule loss → replacement."
        case .clayTile:
            return "HAAG: Any visible broken or cracked tile qualifies for replacement of that tile. > 10% broken tiles on slope → full slope replacement."
        case .concreteTile:
            return "HAAG: > 10% broken tiles on slope OR underlayment exposure → replacement."
        case .slate, .syntheticSlate:
            return "HAAG: Any visible cracked, fractured, or displaced slate qualifies for replacement."
        case .woodShake:
            return "HAAG: > 5 hits per 100 sq ft test square OR ≥ 3 broken shakes → replacement. Distinguish from grain-aligned aging splits."
        case .woodShingle, .syntheticShake:
            return "HAAG: Visible fractures with displaced fibers qualify for replacement of affected shingles."
        case .tpo, .epdm, .pvc, .modifiedBitumen:
            return "HAAG: Membrane displacement or > 12 punctures per 100 sq ft OR adhesion failure → replacement of affected area."
        case .unknown:
            return "HAAG: Material not identified — manual inspector judgment required."
        }
    }

    /// Material modifiers that force replacement regardless of count thresholds.
    static func forcesReplacement(layers: Int, isDiscontinued: Bool, brittleness: BrittlenessResult) -> Bool {
        if isDiscontinued { return true }       // can't match discontinued material
        if layers >= 2 { return true }          // code requires tear-off
        if brittleness == .fail { return true }  // repairs not feasible
        return false
    }
}
