import SwiftUI

// MARK: - Inspection Domain

enum RoofMaterial: String, CaseIterable, Identifiable {
    case asphalt3Tab = "3-Tab Asphalt"
    case architectural = "Architectural Asphalt"
    case metal = "Standing Seam Metal"
    case tile = "Clay Tile"
    case wood = "Wood Shake"
    case tpo = "TPO Membrane"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .asphalt3Tab, .architectural: return "square.grid.3x3.fill"
        case .metal: return "square.grid.2x2.fill"
        case .tile: return "rectangle.grid.3x2.fill"
        case .wood: return "tree.fill"
        case .tpo: return "rectangle.fill"
        }
    }
}

enum DamageSeverity: String {
    case clean = "Clean"
    case cosmetic = "Cosmetic"
    case functional = "Functional"
    case totaled = "Total Loss"

    var color: Color {
        switch self {
        case .clean: return Theme.mint
        case .cosmetic: return Theme.amber
        case .functional: return Theme.ember
        case .totaled: return Theme.crimson
        }
    }
    var bg: Color {
        switch self {
        case .clean: return Theme.mintSoft
        case .cosmetic: return Theme.amberSoft
        case .functional: return Theme.emberSoft
        case .totaled: return Color(red: 1.0, green: 0.92, blue: 0.93)
        }
    }
}

enum FindingSeverity: String, CaseIterable {
    case none = "None"
    case minor = "Minor"
    case moderate = "Moderate"
    case severe = "Severe"

    var color: Color {
        switch self {
        case .none: return Theme.mint
        case .minor: return Theme.amber
        case .moderate: return Theme.ember
        case .severe: return Theme.crimson
        }
    }
    var bg: Color {
        switch self {
        case .none: return Theme.mintSoft
        case .minor: return Theme.amberSoft
        case .moderate: return Theme.emberSoft
        case .severe: return Color(red: 1.0, green: 0.92, blue: 0.93)
        }
    }
}

enum ClaimWorthiness: String {
    case notClaimable = "Not Claimable"
    case borderline = "Borderline"
    case claimable = "Claimable"
    case urgent = "Urgent"

    var color: Color {
        switch self {
        case .notClaimable: return Theme.inkFaint
        case .borderline: return Theme.amber
        case .claimable: return Theme.ember
        case .urgent: return Theme.crimson
        }
    }
    var icon: String {
        switch self {
        case .notClaimable: return "checkmark.shield.fill"
        case .borderline: return "exclamationmark.circle.fill"
        case .claimable: return "doc.badge.plus"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
    var caption: String {
        switch self {
        case .notClaimable: return "Below carrier threshold"
        case .borderline: return "Re-inspect or supplement"
        case .claimable: return "File claim with carrier"
        case .urgent: return "Tarp & file within 48h"
        }
    }
}

struct InspectionFinding: Identifiable, Hashable {
    let id = UUID()
    let label: String      // e.g. "wind_creased_shingles"
    let display: String    // human friendly
    let value: String      // "12 hits / 100 sq ft"
    let confidence: Int    // 0-100
    let icon: String
    let tint: Color
    let detected: Bool
    let severity: FindingSeverity
}

struct StructuralInput: Identifiable {
    let id = UUID()
    let key: String
    let label: String
    let value: String
    let icon: String
}

// MARK: - AI Damage Markers (overlay on photos)

/// Locked damage taxonomy — EXACTLY the 13 pitch-deck categories. `.other`
/// is retained only as an internal fallback for genuinely unknown tokens and
/// is never emitted by the model. Backward-compatible aliases below keep older
/// call sites compiling after the rename.
enum DamageMarkerType: String, CaseIterable {
    case hailHits = "hail_hits"
    case bruising = "bruising"
    case granuleLoss = "granule_loss"
    case windDamage = "wind_damage"
    case windCreasing = "wind_creasing"
    case blistering = "blistering"
    case cracking = "cracking"
    case flashing = "flashing"
    case algaeMoss = "algae_moss"
    case missingShingles = "missing_shingles"
    case splitting = "splitting"
    case lifted = "lifted"
    case structuralSagging = "structural_sagging"
    case other = "other"   // internal fallback only — not one of the 13 categories

    var display: String {
        switch self {
        case .hailHits: return "Hail Hits"
        case .bruising: return "Bruising"
        case .granuleLoss: return "Granule Loss"
        case .windDamage: return "Wind Damage"
        case .windCreasing: return "Wind Creasing"
        case .blistering: return "Blistering"
        case .cracking: return "Cracking"
        case .flashing: return "Flashing"
        case .algaeMoss: return "Algae / Moss"
        case .missingShingles: return "Missing Shingles"
        case .splitting: return "Splitting"
        case .lifted: return "Lifted"
        case .structuralSagging: return "Structural Sagging"
        case .other: return "Damage"
        }
    }

    var pluralDisplay: String {
        switch self {
        case .hailHits: return "hail hits"
        case .bruising: return "bruises"
        case .granuleLoss: return "granule loss spots"
        case .windDamage: return "wind damage areas"
        case .windCreasing: return "wind creases"
        case .blistering: return "blisters"
        case .cracking: return "cracks"
        case .flashing: return "flashing issues"
        case .algaeMoss: return "algae patches"
        case .missingShingles: return "missing shingles"
        case .splitting: return "splits"
        case .lifted: return "lifted tabs"
        case .structuralSagging: return "sagging areas"
        case .other: return "damage points"
        }
    }

    var icon: String {
        switch self {
        case .hailHits: return "circle.hexagongrid.fill"
        case .bruising: return "circle.circle.fill"
        case .granuleLoss: return "circle.dotted"
        case .windDamage: return "tornado"
        case .windCreasing: return "wind"
        case .blistering: return "circle.grid.cross.fill"
        case .cracking: return "bolt.horizontal.fill"
        case .flashing: return "square.stack.3d.up.slash.fill"
        case .algaeMoss: return "leaf.fill"
        case .missingShingles: return "square.dashed"
        case .splitting: return "bolt.horizontal"
        case .lifted: return "arrow.up.square.fill"
        case .structuralSagging: return "arrow.down.right.and.arrow.up.left"
        case .other: return "exclamationmark.triangle.fill"
        }
    }

    /// Per-category overlay hue (PhotoDamageOverlayView + LiveMarkerLayer).
    /// All values come from Theme palette tokens — no inline hex here.
    var color: Color {
        switch self {
        case .hailHits: return Theme.dmgHail               // orange
        case .bruising: return Theme.dmgBruise             // ember
        case .granuleLoss: return Theme.dmgGranule         // amber
        case .windDamage: return Theme.dmgWind             // magenta
        case .windCreasing: return Theme.dmgCrease         // deep red
        case .blistering: return Theme.dmgBlister          // yellow
        case .cracking: return Theme.dmgCrack              // slate
        case .splitting: return Theme.dmgSplit             // slate light
        case .flashing: return Theme.dmgFlashing           // gray
        case .algaeMoss: return Theme.dmgAlgae             // green
        case .missingShingles: return Theme.dmgMissing     // blue
        case .lifted: return Theme.dmgLifted               // teal
        case .structuralSagging: return Theme.dmgSag       // deep purple
        case .other: return Theme.amber
        }
    }
}

extension DamageMarkerType {
    // Backward-compatible aliases so existing expression call sites keep
    // compiling after the rename (these resolve to the new canonical cases).
    // NOTE: usable in expressions only, not in `switch case` patterns.
    static let hailStrike = DamageMarkerType.hailHits
    static let crack = DamageMarkerType.cracking
    static let windCrease = DamageMarkerType.windCreasing
    static let missingShingle = DamageMarkerType.missingShingles
    static let blister = DamageMarkerType.blistering
    static let algae = DamageMarkerType.algaeMoss
}

struct DamageMarker: Identifiable {
    let id = UUID()
    let x: CGFloat       // 0-1 normalized
    let y: CGFloat       // 0-1 normalized
    let radius: CGFloat  // 0-1 normalized (relative to min image dimension)
    let type: DamageMarkerType
    let severity: FindingSeverity
    let note: String
    let confidence: Int  // 0-100 from Gemini

    init(x: CGFloat, y: CGFloat, radius: CGFloat,
         type: DamageMarkerType, severity: FindingSeverity,
         note: String, confidence: Int = 0) {
        self.x = x; self.y = y; self.radius = radius
        self.type = type; self.severity = severity
        self.note = note; self.confidence = confidence
    }
}

struct DetectedHit: Identifiable {
    let id = UUID()
    let x: CGFloat   // 0-1
    let y: CGFloat
    let size: CGFloat // 0-1
    let severity: DamageSeverity
}

// MARK: - Mock Analysis Result

enum InspectionMock {
    static let findings: [InspectionFinding] = [
        .init(label: "granule_loss", display: "Granule Loss",
              value: "Heavy on SW slope · gutter sample",
              confidence: 94, icon: "circle.dotted",
              tint: Theme.ember, detected: true, severity: .severe),
        .init(label: "missing_shingles", display: "Missing Shingles",
              value: "2 tabs · NE slope",
              confidence: 96, icon: "square.dashed",
              tint: Theme.crimson, detected: true, severity: .severe),
        .init(label: "wind_creasing", display: "Wind Creasing",
              value: "8 creases on ridge",
              confidence: 88, icon: "wind",
              tint: Theme.ember, detected: true, severity: .moderate),
        .init(label: "blistering", display: "Blistering",
              value: "Cluster of 14 raised pockets",
              confidence: 82, icon: "circle.grid.cross.fill",
              tint: Theme.amber, detected: true, severity: .moderate),
        .init(label: "cracking_splitting", display: "Cracking / Splitting",
              value: "Hairline splits · W slope",
              confidence: 76, icon: "bolt.horizontal.fill",
              tint: Theme.amber, detected: true, severity: .minor),
        .init(label: "flashing_damage", display: "Flashing Damage",
              value: "Step flashing lifted at chimney",
              confidence: 84, icon: "square.stack.3d.up.slash.fill",
              tint: Theme.ember, detected: true, severity: .moderate),
        .init(label: "algae_moss", display: "Algae / Moss",
              value: "Light staining · N slope",
              confidence: 71, icon: "leaf.fill",
              tint: Theme.mint, detected: true, severity: .minor),
        .init(label: "ponding_water", display: "Ponding Water",
              value: "Not detected",
              confidence: 92, icon: "drop.fill",
              tint: Theme.sky, detected: false, severity: .none),
        .init(label: "bruising", display: "Bruising",
              value: "23 hits / 100 sq ft · mat fracture",
              confidence: 91, icon: "circle.hexagongrid.fill",
              tint: Theme.crimson, detected: true, severity: .severe),
        .init(label: "structural_sagging", display: "Structural Sagging",
              value: "Decking sound · no deflection",
              confidence: 88, icon: "arrow.down.right.and.arrow.up.left",
              tint: Theme.mint, detected: false, severity: .none)
    ]

    static let damageScore: Int = 78
    static let claimWorthiness: ClaimWorthiness = .urgent

    static let inputs: [StructuralInput] = [
        .init(key: "number_of_slopes", label: "Slopes", value: "6", icon: "triangle.fill"),
        .init(key: "age_of_roof", label: "Age", value: "11 yrs", icon: "calendar"),
        .init(key: "material_type", label: "Material", value: "Architectural Asphalt", icon: "square.grid.3x3.fill"),
        .init(key: "pitch", label: "Pitch", value: "7/12", icon: "arrow.up.right")
    ]

    static let damageMarkers: [DamageMarker] = [
        .init(x: 0.22, y: 0.32, radius: 0.04, type: .hailStrike, severity: .severe, note: "Mat fracture, granules displaced"),
        .init(x: 0.34, y: 0.28, radius: 0.035, type: .hailStrike, severity: .moderate, note: "Bruise, soft to touch"),
        .init(x: 0.45, y: 0.40, radius: 0.045, type: .hailStrike, severity: .severe, note: "Penetrating impact"),
        .init(x: 0.58, y: 0.36, radius: 0.03, type: .hailStrike, severity: .minor, note: "Granule scuff"),
        .init(x: 0.62, y: 0.52, radius: 0.05, type: .hailStrike, severity: .severe, note: "Mat exposed"),
        .init(x: 0.30, y: 0.55, radius: 0.035, type: .hailStrike, severity: .moderate, note: "Bruising on tab"),
        .init(x: 0.72, y: 0.45, radius: 0.04, type: .hailStrike, severity: .severe, note: "Multiple impacts"),
        .init(x: 0.50, y: 0.62, radius: 0.035, type: .hailStrike, severity: .moderate, note: "Hail bruise"),
        .init(x: 0.40, y: 0.70, radius: 0.045, type: .hailStrike, severity: .severe, note: "Mat fracture"),
        .init(x: 0.66, y: 0.66, radius: 0.03, type: .hailStrike, severity: .minor, note: "Granule loss spot"),
        .init(x: 0.20, y: 0.48, radius: 0.05, type: .crack, severity: .moderate, note: "Hairline split through tab"),
        .init(x: 0.78, y: 0.58, radius: 0.045, type: .crack, severity: .minor, note: "Surface crack"),
        .init(x: 0.15, y: 0.20, radius: 0.06, type: .granuleLoss, severity: .severe, note: "Bare patch"),
        .init(x: 0.85, y: 0.30, radius: 0.05, type: .windCrease, severity: .moderate, note: "Crease at nail line")
    ]

    static let hits: [DetectedHit] = [
        .init(x: 0.22, y: 0.32, size: 0.06, severity: .functional),
        .init(x: 0.34, y: 0.28, size: 0.05, severity: .cosmetic),
        .init(x: 0.45, y: 0.40, size: 0.07, severity: .functional),
        .init(x: 0.58, y: 0.36, size: 0.04, severity: .cosmetic),
        .init(x: 0.62, y: 0.52, size: 0.08, severity: .totaled),
        .init(x: 0.30, y: 0.55, size: 0.05, severity: .cosmetic),
        .init(x: 0.72, y: 0.45, size: 0.06, severity: .functional),
        .init(x: 0.50, y: 0.62, size: 0.05, severity: .cosmetic),
        .init(x: 0.40, y: 0.70, size: 0.07, severity: .functional),
        .init(x: 0.66, y: 0.66, size: 0.04, severity: .cosmetic),
        .init(x: 0.20, y: 0.48, size: 0.05, severity: .cosmetic),
        .init(x: 0.78, y: 0.58, size: 0.06, severity: .functional)
    ]
}
