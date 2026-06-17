import Foundation

// MARK: - Inspection → HaagInspectionInput

/// Bridges the app's editable `Inspection` model into the rigorous,
/// fully-traceable `HaagDecisionEngine` input. Pure mapping — no I/O.
///
/// This is the single conversion point that lets both the in-app verdict
/// UI (via `DecisionEngine.decide`) and the PDF report (`HaagReportGenerator`)
/// share one published-threshold decision engine, so the numbers never drift.
extension HaagInspectionInput {

    static func from(_ inspection: Inspection) -> HaagInspectionInput {
        let covering = HaagRoofCovering.from(inspection.roof.primaryMaterial)
        let isMetal = covering == .metalPanel
        let usesTileRule = covering.damagedPercentThreshold != nil

        let slopes: [HaagSlopeInput] = inspection.slopes.map { slope in
            let hail = slope.damageTypes.hail
            let wind = slope.damageTypes.wind

            // Functional hail/impact hits logged on this slope.
            let hailHits = hail.asphaltBruise
                + hail.asphaltMatFracture
                + hail.asphaltGranuleLossExposed
            // Functional wind hits.
            let windHits = wind.shingleCrease
                + wind.shingleMissing
                + wind.shingleLiftedUnsealed

            let hits = HaagHitCounts(
                functionalHail: isMetal ? 0 : hailHits,
                functionalWind: windHits,
                functionalCrack: 0,
                functionalMetalDent: isMetal ? hailHits : 0,
                cosmetic: 0
            )

            // Preserve prior density semantics: a slope with logged damage but
            // no explicit test-square count is treated as one 100 sq ft square
            // rather than being dropped to "insufficient data".
            let testSquares = Double(max(1, slope.testSquareCount))

            // Tile / slate coverings evaluate by % of damaged units. We don't
            // store explicit tile counts, so approximate visible tiles from the
            // slope area (~100 tiles per 100 sq ft square) and treat logged
            // hits as damaged tiles.
            var tileCounts: HaagTileCounts? = nil
            if usesTileRule {
                let effectiveSquares = slope.detectedAreaSquares ?? slope.areaSquares
                let visible = Int(max(1.0, effectiveSquares * 100.0).rounded())
                let damaged = min(visible, hailHits + windHits)
                tileCounts = HaagTileCounts(visibleTiles: visible, damagedTiles: damaged)
            }

            return HaagSlopeInput(
                id: slope.orientation,
                name: "\(slope.orientation) Slope",
                orientation: slope.orientation,
                pitch: "\(slope.pitchRiseOver12)/12",
                approxSquares: slope.detectedAreaSquares ?? slope.areaSquares,
                testSquaresPhotographed: testSquares,
                hits: hits,
                tileCounts: tileCounts,
                membraneBreach: false,
                photoIds: []
            )
        }

        let flags = HaagContextFlags(
            matchingDiscontinued: false,
            doubleLayerPresent: inspection.roof.layers >= 2,
            structuralDamage: false,
            beyondServiceLife: inspection.roof.estimatedAgeYears > 25,
            jurisdictionTwentyFiveRule: false
        )

        return HaagInspectionInput(
            propertyId: inspection.job.propertyAddress.isEmpty ? nil : inspection.job.propertyAddress,
            inspectionId: inspection.job.reportId,
            inspectedAt: inspection.job.inspectionDate,
            roofCovering: covering,
            roofAgeYears: inspection.roof.estimatedAgeYears,
            totalSlopes: inspection.slopes.count,
            slopes: slopes,
            contextFlags: flags
        )
    }
}

extension HaagRoofCovering {
    /// Maps the app's editable roof-material enum onto the engine's covering.
    static func from(_ material: RoofPrimaryMaterial) -> HaagRoofCovering {
        switch material {
        case .asphaltShingle, .threeTabAsphalt: return .asphaltComposition
        case .metalPanel:                       return .metalPanel
        case .woodShake:                        return .woodShakeShingle
        case .concreteTile:                     return .concreteTile
        case .clayTile:                         return .clayTile
        }
    }
}
