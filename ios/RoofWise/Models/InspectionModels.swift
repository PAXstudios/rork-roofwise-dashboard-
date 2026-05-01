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

struct InspectionFinding: Identifiable {
    let id = UUID()
    let label: String      // e.g. "wind_creased_shingles"
    let display: String    // human friendly
    let value: String      // "12 hits / 100 sq ft"
    let confidence: Int    // 0-100
    let icon: String
    let tint: Color
    let detected: Bool
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
        .init(label: "hail_hits",
              display: "Hail Hits",
              value: "23 hits · SW slope",
              confidence: 94, icon: "circle.hexagongrid.fill",
              tint: Theme.crimson, detected: true),
        .init(label: "wind_creased_shingles",
              display: "Wind-Creased Shingles",
              value: "8 creases on ridge",
              confidence: 88, icon: "wind",
              tint: Theme.ember, detected: true),
        .init(label: "missing_shingles",
              display: "Missing Shingles",
              value: "2 tabs · NE slope",
              confidence: 96, icon: "square.dashed",
              tint: Theme.crimson, detected: true),
        .init(label: "functional_damage_present",
              display: "Functional Damage",
              value: "Mat fracture confirmed",
              confidence: 81, icon: "exclamationmark.triangle.fill",
              tint: Theme.ember, detected: true),
        .init(label: "granule_loss",
              display: "Granule Loss",
              value: "Heavy · gutter sample",
              confidence: 92, icon: "circle.dotted",
              tint: Theme.amber, detected: true)
    ]

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
