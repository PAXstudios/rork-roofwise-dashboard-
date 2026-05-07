import Foundation

// MARK: - Domain

/// Material families the estimator knows how to price. Aligned to the
/// existing `RoofPrimaryMaterial` set from the Inspection schema, plus a
/// couple of asphalt sub-tiers since the price spread between 3-tab,
/// architectural, and designer asphalt is larger than between materials.
nonisolated enum EstimateMaterial: String, CaseIterable, Identifiable, Hashable, Sendable {
    case asphalt3Tab     = "asphalt_3tab"
    case asphaltArch     = "asphalt_arch"
    case asphaltDesigner = "asphalt_designer"
    case metalStanding   = "metal_standing_seam"
    case woodShake       = "wood_shake"
    case concreteTile    = "concrete_tile"
    case clayTile        = "clay_tile"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .asphalt3Tab:     return "3-Tab Asphalt"
        case .asphaltArch:     return "Architectural Asphalt"
        case .asphaltDesigner: return "Designer Asphalt"
        case .metalStanding:   return "Standing Seam Metal"
        case .woodShake:       return "Wood Shake"
        case .concreteTile:    return "Concrete Tile"
        case .clayTile:        return "Clay Tile"
        }
    }

    /// Industry baseline installed cost ($/sq), good-tier, simple gable,
    /// single layer tear-off included. Sourced from 2025 RSMeans / HomeAdvisor
    /// regional medians.
    var basePerSquare: Double {
        switch self {
        case .asphalt3Tab:     return 400
        case .asphaltArch:     return 475
        case .asphaltDesigner: return 675
        case .metalStanding:   return 1100
        case .woodShake:       return 850
        case .concreteTile:    return 900
        case .clayTile:        return 1500
        }
    }

    /// SF Symbol used in the chip selector.
    var symbol: String {
        switch self {
        case .asphalt3Tab, .asphaltArch, .asphaltDesigner: return "house.fill"
        case .metalStanding: return "square.grid.3x3.fill"
        case .woodShake:     return "leaf.fill"
        case .concreteTile, .clayTile: return "square.stack.3d.up.fill"
        }
    }
}

nonisolated enum EstimateQuality: String, CaseIterable, Identifiable, Hashable, Sendable {
    case good, better, best
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    /// Multiplier on baseline material+labor.
    var multiplier: Double {
        switch self {
        case .good:   return 1.00
        case .better: return 1.15
        case .best:   return 1.35
        }
    }
    var subtitle: String {
        switch self {
        case .good:   return "Standard 3-tab grade"
        case .better: return "Mid-tier laminate"
        case .best:   return "Lifetime / impact-rated"
        }
    }
}

nonisolated enum EstimateComplexity: String, CaseIterable, Identifiable, Hashable, Sendable {
    case simple, average, complex, custom
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    /// Multiplier capturing geometry + steepness + accessibility.
    var multiplier: Double {
        switch self {
        case .simple:  return 0.95   // single gable, walkable pitch
        case .average: return 1.10   // typical hip + valleys
        case .complex: return 1.30   // multiple gables/dormers/valleys
        case .custom:  return 1.55   // mansard, turrets, very steep
        }
    }
    var subtitle: String {
        switch self {
        case .simple:  return "Single gable · walkable"
        case .average: return "Hip · few valleys"
        case .complex: return "Multi-gable · dormers"
        case .custom:  return "Mansard · turrets · steep"
        }
    }
}

nonisolated struct CostEstimateInput: Hashable, Sendable {
    var address: String
    var totalSquares: Double
    var detectedSegmentCount: Int
    var avgPitchRiseOver12: Int
    var material: EstimateMaterial
    var quality: EstimateQuality
    var complexity: EstimateComplexity
    var tearOffLayers: Int          // 1, 2, 3
    var includePermit: Bool
    var includeDisposal: Bool
}

nonisolated struct CostEstimateLineItem: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let detail: String
    let amount: Double
}

nonisolated struct CostEstimate: Hashable, Sendable {
    let input: CostEstimateInput
    let lineItems: [CostEstimateLineItem]
    let subtotal: Double
    /// Conservative low-end (subtotal × 0.92).
    let low: Double
    /// Stretch high-end (subtotal × 1.12).
    let high: Double
    let pricePerSquare: Double
    let createdAt: Date

    var rangeLabel: String {
        "\(currency(low)) – \(currency(high))"
    }
}

// MARK: - Currency helpers

private nonisolated let _currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f
}()

nonisolated func currency(_ v: Double) -> String {
    _currencyFormatter.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}

// MARK: - Engine

nonisolated enum CostEstimator {

    /// Pure function. Same input → same output. No I/O.
    static func estimate(_ input: CostEstimateInput) -> CostEstimate {
        let squares = max(1.0, input.totalSquares)

        // 1. Base material + labor
        let materialBase = input.material.basePerSquare * input.quality.multiplier
        let materialLine = materialBase * squares

        // 2. Complexity surcharge (applied as delta over baseline so we can show it)
        let complexityDelta = (input.complexity.multiplier - 1.0) * materialLine

        // 3. Steepness premium (≥7:12 adds 8%, ≥10:12 adds 22%)
        let steepMultiplier: Double
        switch input.avgPitchRiseOver12 {
        case ..<7:  steepMultiplier = 0.0
        case 7...9: steepMultiplier = 0.08
        default:    steepMultiplier = 0.22
        }
        let steepLine = steepMultiplier * materialLine

        // 4. Tear-off (single layer included; each extra layer = $90/sq)
        let extraLayers = max(0, input.tearOffLayers - 1)
        let tearOffLine = Double(extraLayers) * 90.0 * squares

        // 5. Disposal & permit (simple flat add-ons)
        let disposalLine = input.includeDisposal ? max(450, 35.0 * squares) : 0
        let permitLine   = input.includePermit ? 285.0 : 0

        var items: [CostEstimateLineItem] = [
            .init(id: "mat",
                  label: "\(input.material.displayName) · \(input.quality.displayName.lowercased())",
                  detail: String(format: "%.1f sq × %@/sq", squares, currency(materialBase)),
                  amount: materialLine),
            .init(id: "complex",
                  label: "\(input.complexity.displayName) roof complexity",
                  detail: String(format: "%+.0f%% of material+labor",
                                 (input.complexity.multiplier - 1.0) * 100),
                  amount: complexityDelta)
        ]
        if steepLine > 0 {
            items.append(.init(
                id: "steep",
                label: "Steep-pitch premium (\(input.avgPitchRiseOver12):12)",
                detail: String(format: "%+.0f%% steep-roof labor", steepMultiplier * 100),
                amount: steepLine
            ))
        }
        if tearOffLine > 0 {
            items.append(.init(
                id: "tear",
                label: "Extra tear-off (\(extraLayers) layer\(extraLayers == 1 ? "" : "s"))",
                detail: String(format: "%.1f sq × $90/sq", squares),
                amount: tearOffLine
            ))
        }
        if disposalLine > 0 {
            items.append(.init(
                id: "disp",
                label: "Dumpster & disposal",
                detail: "Hauling + landfill fees",
                amount: disposalLine
            ))
        }
        if permitLine > 0 {
            items.append(.init(
                id: "permit",
                label: "City permit",
                detail: "Filed by contractor",
                amount: permitLine
            ))
        }

        let subtotal = items.reduce(0.0) { $0 + $1.amount }

        return CostEstimate(
            input: input,
            lineItems: items,
            subtotal: subtotal,
            low: subtotal * 0.92,
            high: subtotal * 1.12,
            pricePerSquare: subtotal / squares,
            createdAt: .now
        )
    }
}
