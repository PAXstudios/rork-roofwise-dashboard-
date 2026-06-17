import Foundation

// MARK: - Forensic Detection Taxonomy
//
// The expanded, material-specific damage taxonomy used by the per-photo
// detection pipeline (Stages 1-3). Every case maps cleanly to one of the
// HAAG threshold rules in `HaagThresholds.swift`. Unlike the legacy 13-token
// `DamageMarkerType` (used for overlay rendering), this taxonomy carries the
// forensic distinctions HAAG requires — e.g. cosmetic vs functional metal
// dents, missing tab vs whole missing shingle, storm vs non-storm causes.

nonisolated enum ForensicDamageType: String, CaseIterable, Codable, Sendable {
    // Asphalt shingles (3-tab + laminate/architectural)
    case hailHit = "hail_hit"
    case bruising = "bruising"
    case granuleLoss = "granule_loss"
    case matTransfer = "mat_transfer"
    case windCreasing = "wind_creasing"
    case missingTab = "missing_tab"
    case missingShingle = "missing_shingle"
    case lifted = "lifted"
    case cracking = "cracking"
    case splitting = "splitting"
    case blistering = "blistering"
    case flashingDamage = "flashing_damage"
    case algaeMoss = "algae_moss"
    case footfallDamage = "footfall_damage"

    // Metal panel
    case metalDentCosmetic = "metal_dent_cosmetic"
    case metalDentFunctional = "metal_dent_functional"
    case seamDisengagement = "seam_disengagement"
    case fastenerPullout = "fastener_pullout"

    // Tile (clay / concrete)
    case tileCracked = "tile_cracked"
    case tileBroken = "tile_broken"
    case tileDisplaced = "tile_displaced"
    case underlaymentExposure = "underlayment_exposure"

    // Slate
    case slateCracked = "slate_cracked"
    case slateDisplaced = "slate_displaced"
    case slateCornerBroken = "slate_corner_broken"

    // Wood shake / shingle
    case woodSplitWithGrain = "wood_split_with_grain"
    case woodFracture = "wood_fracture"
    case woodGranularCrushing = "wood_granular_crushing"

    // Commercial flat (TPO / EPDM / PVC / mod-bit)
    case membranePuncture = "membrane_puncture"
    case membraneDisplacement = "membrane_displacement"
    case adhesionFailure = "adhesion_failure"
    case surfaceAbrasion = "surface_abrasion"
    case seamSplit = "seam_split"

    // Universal (any material)
    case structuralSagging = "structural_sagging"

    /// Human-friendly label.
    var displayName: String {
        switch self {
        case .hailHit: return "Hail Hit"
        case .bruising: return "Bruising"
        case .granuleLoss: return "Granule Loss"
        case .matTransfer: return "Mat Transfer"
        case .windCreasing: return "Wind Creasing"
        case .missingTab: return "Missing Tab"
        case .missingShingle: return "Missing Shingle"
        case .lifted: return "Lifted Tab"
        case .cracking: return "Cracking"
        case .splitting: return "Splitting"
        case .blistering: return "Blistering"
        case .flashingDamage: return "Flashing Damage"
        case .algaeMoss: return "Algae / Moss"
        case .footfallDamage: return "Footfall Damage"
        case .metalDentCosmetic: return "Metal Dent (Cosmetic)"
        case .metalDentFunctional: return "Metal Dent (Functional)"
        case .seamDisengagement: return "Seam Disengagement"
        case .fastenerPullout: return "Fastener Pullout"
        case .tileCracked: return "Tile Cracked"
        case .tileBroken: return "Tile Broken"
        case .tileDisplaced: return "Tile Displaced"
        case .underlaymentExposure: return "Underlayment Exposure"
        case .slateCracked: return "Slate Cracked"
        case .slateDisplaced: return "Slate Displaced"
        case .slateCornerBroken: return "Slate Corner Broken"
        case .woodSplitWithGrain: return "Wood Split (With Grain)"
        case .woodFracture: return "Wood Fracture"
        case .woodGranularCrushing: return "Wood Granular Crushing"
        case .membranePuncture: return "Membrane Puncture"
        case .membraneDisplacement: return "Membrane Displacement"
        case .adhesionFailure: return "Adhesion Failure"
        case .surfaceAbrasion: return "Surface Abrasion"
        case .seamSplit: return "Seam Split"
        case .structuralSagging: return "Structural Sagging"
        }
    }

    /// True for damage that HAAG treats as NON-storm — must be ruled out and
    /// never attributed to a storm event.
    var isNonStormByDefinition: Bool {
        switch self {
        case .blistering, .algaeMoss, .footfallDamage, .woodSplitWithGrain, .metalDentCosmetic:
            return true
        default:
            return false
        }
    }

    /// The damage types valid for a given material category. Drives the
    /// material-specific forensic detection prompt (Stage 2).
    static func types(for category: HaagRoofMaterial.MaterialCategory) -> [ForensicDamageType] {
        let universal: [ForensicDamageType] = [.structuralSagging]
        switch category {
        case .threeTab, .laminate:
            return [.hailHit, .bruising, .granuleLoss, .matTransfer, .windCreasing,
                    .missingTab, .missingShingle, .lifted, .cracking, .splitting,
                    .blistering, .flashingDamage, .algaeMoss, .footfallDamage] + universal
        case .metal:
            return [.metalDentCosmetic, .metalDentFunctional, .seamDisengagement,
                    .granuleLoss, .fastenerPullout, .flashingDamage] + universal
        case .tile:
            return [.tileCracked, .tileBroken, .tileDisplaced, .underlaymentExposure,
                    .flashingDamage] + universal
        case .slate:
            return [.slateCracked, .slateDisplaced, .slateCornerBroken,
                    .flashingDamage] + universal
        case .wood:
            return [.woodSplitWithGrain, .woodFracture, .woodGranularCrushing,
                    .hailHit, .flashingDamage] + universal
        case .commercialFlat:
            return [.membranePuncture, .membraneDisplacement, .adhesionFailure,
                    .surfaceAbrasion, .seamSplit, .flashingDamage] + universal
        case .unknown:
            return ForensicDamageType.allCases
        }
    }
}

// MARK: - Severity

nonisolated enum ForensicSeverity: String, Codable, Sendable, CaseIterable {
    case minor
    case moderate
    case severe

    /// Maps to the app-wide `FindingSeverity` for overlay/rendering reuse.
    var findingSeverity: FindingSeverity {
        switch self {
        case .minor: return .minor
        case .moderate: return .moderate
        case .severe: return .severe
        }
    }
}

// MARK: - A single forensic detection

/// One distinct visible damage instance produced by the detection pipeline.
/// `box2d` is Gemini's native [ymin, xmin, ymax, xmax] format normalized to
/// 0-1000. There is NO count limit — the pipeline reports every instance and
/// Swift aggregation (Stage 4) handles counting.
nonisolated struct ForensicDetection: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    let damageType: ForensicDamageType
    /// [ymin, xmin, ymax, xmax] in 0-1000 (Gemini native). May be nil if the
    /// model only returned a point/region without a tight box.
    let box2d: [Int]?
    /// Required 1-2 sentence visible-evidence description.
    let evidence: String
    let severity: ForensicSeverity
    /// Whether this damage is attributable to a storm event (vs wear/defect/foot traffic).
    let isStormAttributable: Bool
    /// Whether this qualifies as functional damage under HAAG (vs cosmetic only).
    let isFunctionalDamage: Bool
    /// 0-100.
    let confidence: Int

    private enum CodingKeys: String, CodingKey {
        case damageType = "damage_type"
        case box2d = "box_2d"
        case evidence
        case severity
        case isStormAttributable = "is_storm_attributable"
        case isFunctionalDamage = "is_functional_damage"
        case confidence
    }

    /// Center point (x, y) in 0-1 normalized image space, derived from box2d.
    var normalizedCenter: (x: Double, y: Double)? {
        guard let b = box2d, b.count == 4 else { return nil }
        let yMin = Double(min(b[0], b[2])) / 1000.0
        let xMin = Double(min(b[1], b[3])) / 1000.0
        let yMax = Double(max(b[0], b[2])) / 1000.0
        let xMax = Double(max(b[1], b[3])) / 1000.0
        return ((xMin + xMax) / 2.0, (yMin + yMax) / 2.0)
    }
}

// MARK: - Material classification (Stage 1)

nonisolated struct MaterialClassification: Codable, Sendable {
    let material: HaagRoofMaterial
    let confidence: Int       // 0-100
    let evidence: String
}

// MARK: - Image quality (Stage 0)

nonisolated struct ImageQualityReport: Codable, Sendable {
    let passed: Bool
    /// 0-1 sharpness proxy (higher = sharper).
    let sharpness: Double
    /// 0-1 mean luminance.
    let brightness: Double
    /// Shortest pixel edge of the source image.
    let minDimension: Int
    /// Human-readable reasons the image failed (empty when passed).
    let reasons: [String]
}

// MARK: - Per-photo pipeline result

/// The complete output of running Stages 0-3 on one captured photo.
nonisolated struct PhotoDetectionResult: Sendable {
    let quality: ImageQualityReport
    let classification: MaterialClassification?
    /// Verified detections (post Stage 3 self-critique). No count limit.
    let detections: [ForensicDetection]
    /// True when the API call could not be completed.
    var failed: Bool = false
    /// User-facing reason when `failed` or quality-gated.
    var failureReason: String? = nil
    /// True when Gemini reports the photo does not show a roof at all.
    var noRoofDetected: Bool = false

    var meanConfidence: Double {
        guard !detections.isEmpty else { return 0 }
        return detections.reduce(0.0) { $0 + Double($1.confidence) } / Double(detections.count)
    }
}
