import SwiftUI

enum SlopeType: String, CaseIterable, Identifiable {
    case leftSlope = "Left Slope"
    case rightSlope = "Right Slope"
    case frontSlope = "Front Slope (Street-Facing)"
    case backSlope = "Back Slope"
    case ridgeLine = "Ridge Line"
    case valley = "Valley"
    case guttersFascia = "Gutters & Fascia"
    case soffit = "Soffit"
    case chimneyFlashing = "Chimney & Flashing"
    case pipeBoots = "Pipe Boots & Vents"
    case skylights = "Skylights"
    case hipCaps = "Hip Caps"
    case dripEdge = "Drip Edge"
    case siding = "Siding"
    case windowsTrim = "Windows & Trim"
    case garageDoor = "Garage Door"
    case downspouts = "Downspouts"
    case foundation = "Foundation"
    case fenceGate = "Fence/Gate"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .frontSlope: return "Front Slope"
        default: return rawValue
        }
    }

    var icon: String {
        switch self {
        case .leftSlope, .rightSlope, .frontSlope, .backSlope: return "triangle.fill"
        case .ridgeLine: return "line.diagonal"
        case .valley: return "arrow.down.right.and.arrow.up.left"
        case .guttersFascia, .downspouts: return "drop.fill"
        case .soffit: return "rectangle.split.3x1.fill"
        case .chimneyFlashing: return "house.lodge.fill"
        case .pipeBoots: return "circle.circle.fill"
        case .skylights: return "sun.max.fill"
        case .hipCaps: return "triangle"
        case .dripEdge: return "rectangle.bottomthird.inset.filled"
        case .siding: return "rectangle.split.3x3.fill"
        case .windowsTrim: return "rectangle.split.2x2.fill"
        case .garageDoor: return "door.garage.closed"
        case .foundation: return "square.stack.3d.down.right.fill"
        case .fenceGate: return "rectangle.grid.1x2.fill"
        }
    }
}
