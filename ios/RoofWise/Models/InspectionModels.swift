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

struct InspectionFinding: Identifiable {
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
