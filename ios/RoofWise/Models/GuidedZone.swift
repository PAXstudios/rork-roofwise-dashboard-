import SwiftUI

/// Required zones in the guided inspection flow. The order here is the order
/// the rep is walked through; each zone has a target SlopeType + capture mode
/// and a minimum photo count to be considered "complete".
enum GuidedZone: String, CaseIterable, Identifiable {
    case frontSlope
    case backSlope
    case leftSlope
    case rightSlope
    case ridge
    case valleys
    case vents
    case flashing
    case gutters
    case dripEdge
    case closeUpDamage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frontSlope: return "Front Slope"
        case .backSlope: return "Back Slope"
        case .leftSlope: return "Left Slope"
        case .rightSlope: return "Right Slope"
        case .ridge: return "Ridge"
        case .valleys: return "Valleys"
        case .vents: return "Vents"
        case .flashing: return "Flashing"
        case .gutters: return "Gutters"
        case .dripEdge: return "Drip Edge"
        case .closeUpDamage: return "Close-up Damage"
        }
    }

    var subtitle: String {
        switch self {
        case .frontSlope: return "Wide shot, street-facing"
        case .backSlope: return "Wide shot, opposite side"
        case .leftSlope: return "Side view, gable to ridge"
        case .rightSlope: return "Side view, gable to ridge"
        case .ridge: return "Top capping line"
        case .valleys: return "Where two slopes meet"
        case .vents: return "Pipe boots & roof vents"
        case .flashing: return "Step / chimney flashing"
        case .gutters: return "Gutter line + downspouts"
        case .dripEdge: return "Eave & rake metal"
        case .closeUpDamage: return "Tight shots of hits"
        }
    }

    var slope: SlopeType {
        switch self {
        case .frontSlope: return .frontSlope
        case .backSlope: return .backSlope
        case .leftSlope: return .leftSlope
        case .rightSlope: return .rightSlope
        case .ridge: return .ridgeLine
        case .valleys: return .valley
        case .vents: return .pipeBoots
        case .flashing: return .chimneyFlashing
        case .gutters: return .guttersFascia
        case .dripEdge: return .dripEdge
        case .closeUpDamage: return .frontSlope
        }
    }

    var captureMode: CaptureMode {
        switch self {
        case .closeUpDamage: return .singleShingle
        default: return .square
        }
    }

    /// Minimum photos required to mark this zone "complete".
    var minPhotos: Int {
        switch self {
        case .closeUpDamage: return 2
        case .vents, .flashing, .gutters, .dripEdge, .valleys, .ridge: return 1
        default: return 1
        }
    }

    var icon: String {
        switch self {
        case .frontSlope, .backSlope, .leftSlope, .rightSlope: return "triangle.fill"
        case .ridge: return "line.diagonal"
        case .valleys: return "arrow.down.right.and.arrow.up.left"
        case .vents: return "circle.circle.fill"
        case .flashing: return "square.stack.3d.up.slash.fill"
        case .gutters: return "drop.fill"
        case .dripEdge: return "rectangle.bottomthird.inset.filled"
        case .closeUpDamage: return "viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .frontSlope, .backSlope, .leftSlope, .rightSlope: return Theme.ember
        case .ridge: return Theme.amber
        case .valleys: return Theme.amber
        case .vents, .flashing: return Theme.sky
        case .gutters, .dripEdge: return Theme.mint
        case .closeUpDamage: return Theme.crimson
        }
    }

    static func match(slope: SlopeType, mode: CaptureMode) -> GuidedZone? {
        if mode == .singleShingle { return .closeUpDamage }
        return GuidedZone.allCases.first { $0.slope == slope && $0.captureMode == .square }
    }
}
