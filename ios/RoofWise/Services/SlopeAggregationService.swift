import Foundation

// MARK: - Slope Aggregation Service (Stages 4-5)
//
// Bridges the per-photo detection pipeline (Stages 0-3) to the RoofWise
// Decision Engine. Pure Swift, deterministic, no I/O:
//
//   Stage 4  Aggregate per-photo PhotoDetectionResults for one slope into a
//            single SlopeAggregateData (sum counts, normalize per-area metrics).
//   Stage 5  Apply HAAG thresholds (HaagThresholds.swift) to produce a
//            per-slope HaagSlopeVerdict the Decision Engine can reason over.
//
// The detection-pipeline `ForensicDamageType` taxonomy is finer-grained than
// the legacy 13-token overlay enum; this layer collapses it into the count
// buckets each HAAG threshold rule needs.

nonisolated enum SlopeAggregationService {

    /// Rough industry estimates used to convert raw counts into the percentage
    /// metrics some HAAG rules require when an exact unit count isn't captured.
    private enum Estimate {
        static let shinglesPerSquare: Double = 80   // ~3 bundles × ~27 shingles
        static let tilesPerSquare: Double = 100     // clay / concrete tile
        static let panelsPerSquare: Double = 4      // standing-seam / panel
    }

    // MARK: - Stage 4: aggregation

    /// Aggregate per-photo `PhotoDetectionResult`s for one slope.
    /// `testSquareAreaSqFt` defaults to 100 (the HAAG standard 10×10 ft square).
    static func aggregate(
        slopeId: UUID,
        orientation: String,
        material: HaagRoofMaterial,
        areaSquares: Double,
        photoResults: [(photoId: UUID, result: PhotoDetectionResult)],
        testSquareAreaSqFt: Double = 100.0
    ) -> SlopeAggregateData {
        var data = SlopeAggregateData()
        data.slopeId = slopeId
        data.orientation = orientation
        data.material = material
        data.areaSquares = areaSquares
        data.photoIds = photoResults.map(\.photoId)

        var matTransferWorst: ForensicSeverity?
        var granuleWorst: ForensicSeverity?

        for (_, result) in photoResults {
            for d in result.detections {
                switch d.damageType {
                case .hailHit: data.hailHitsTotal += 1
                case .bruising: data.bruisingCount += 1
                case .matTransfer: matTransferWorst = worst(matTransferWorst, d.severity)
                case .granuleLoss: granuleWorst = worst(granuleWorst, d.severity)
                case .windCreasing: data.windCreasedCount += 1
                case .missingTab: data.missingTabsCount += 1
                case .missingShingle: data.missingShinglesCount += 1
                case .lifted: data.liftedCount += 1

                case .metalDentFunctional: data.metalDentsFunctionalCount += 1
                case .metalDentCosmetic: data.metalDentsCosmeticCount += 1
                case .seamDisengagement: data.seamDisengagementCount += 1

                case .tileBroken, .tileCracked, .tileDisplaced,
                     .slateCracked, .slateDisplaced, .slateCornerBroken:
                    data.tilesBrokenCount += 1
                case .underlaymentExposure: data.underlaymentExposureCount += 1

                case .membranePuncture: data.puncturesPerHundredSqFt += 1 // raw count; normalized below
                case .adhesionFailure: data.adhesionFailureAreaSqFt += 1   // raw count; treated as area proxy

                case .blistering: data.blistersCount += 1
                case .algaeMoss: data.algaeMossCount += 1
                case .footfallDamage: data.footfallDamageCount += 1

                default:
                    break
                }

                // Harvest non-storm observations for the report's "ruled out" section.
                if d.damageType.isNonStormByDefinition || !d.isStormAttributable {
                    data.collateralObservations.append("\(d.damageType.displayName): \(d.evidence)")
                }
            }
        }

        data.matTransferSeverity = matTransfer(from: matTransferWorst)
        data.granuleLossLevel = granule(from: granuleWorst)

        // Normalize per-area metrics to a 100 sq ft test square.
        let totalSqFt = areaSquares * 100
        let testSquareScale = totalSqFt > 0 ? testSquareAreaSqFt / totalSqFt : 0
        data.hailHitsPerHundredSqFt = Double(data.hailHitsTotal) * testSquareScale
        data.puncturesPerHundredSqFt *= testSquareScale

        // Percentage metrics from estimated unit counts (deterministic fallbacks).
        let estimatedShingles = areaSquares * Estimate.shinglesPerSquare
        if estimatedShingles > 0 {
            data.windPercentDamaged = Double(data.windCreasedCount + data.missingTabsCount) / estimatedShingles
        }
        let estimatedTiles = areaSquares * Estimate.tilesPerSquare
        if estimatedTiles > 0 {
            data.tilesBrokenPercent = Double(data.tilesBrokenCount) / estimatedTiles
        }
        let estimatedPanels = areaSquares * Estimate.panelsPerSquare
        if estimatedPanels > 0 {
            data.metalDentedPanelsPercent = Double(data.metalDentsFunctionalCount) / estimatedPanels
        }

        // Mean confidence across every detection on the slope.
        let allConfidences = photoResults.flatMap { $0.result.detections.map(\.confidence) }
        data.meanDetectionConfidence = allConfidences.isEmpty
            ? 0
            : Double(allConfidences.reduce(0, +)) / Double(allConfidences.count)

        return data
    }

    // MARK: - Stage 5: HAAG threshold application

    /// Apply HAAG thresholds to produce a slope verdict.
    static func applyThresholds(
        data: SlopeAggregateData,
        isDiscontinued: Bool,
        layers: Int,
        brittleness: BrittlenessResult
    ) -> HaagSlopeVerdict {
        let mat = data.material
        let rule = HaagThresholds.rule(for: mat)

        // Forced-replacement modifiers (discontinued / multi-layer / brittle).
        if HaagThresholds.forcesReplacement(layers: layers, isDiscontinued: isDiscontinued, brittleness: brittleness) {
            return HaagSlopeVerdict(
                slopeId: data.slopeId,
                hitsInTestSquare: data.hailHitsTotal,
                threshold: nil,
                thresholdRuleCitation: rule,
                functionalDamageExceedsThreshold: true,
                verdict: .fullReplacement,
                verdictReasoning: "Forced replacement: discontinued=\(isDiscontinued) / layers=\(layers) / brittleness=\(brittleness.rawValue)",
                stormAttributable: data.hailHitsTotal + data.missingShinglesCount + data.windCreasedCount > 0,
                nonStormDamageObserved: nonStormObs(data)
            )
        }

        switch mat.category {
        case .threeTab, .laminate:
            let hailThreshold = HaagThresholds.asphaltHailHitsThreshold(mat)
            let creaseThreshold = HaagThresholds.asphaltCreasedShinglesThreshold(mat)
            let hitsPerSquare = Int(data.hailHitsPerHundredSqFt.rounded())
            let exceedsHail = hitsPerSquare > hailThreshold
            let exceedsCrease = data.windCreasedCount >= creaseThreshold
            let exceedsWindPct = mat == .architecturalAsphalt && data.windPercentDamaged > HaagThresholds.laminateWindDamagePercentThreshold

            let qualifies = exceedsHail || exceedsCrease || exceedsWindPct
            let anyDamage = data.hailHitsTotal + data.windCreasedCount + data.missingShinglesCount > 0
            let verdict: SlopeVerdict = qualifies ? .fullReplacement : (anyDamage ? .repair : .noDamage)
            let reasoning = "hits/100sf=\(hitsPerSquare) vs threshold \(hailThreshold); creased=\(data.windCreasedCount) vs \(creaseThreshold); wind%=\(pct(data.windPercentDamaged)) vs 5%"

            return HaagSlopeVerdict(
                slopeId: data.slopeId, hitsInTestSquare: hitsPerSquare, threshold: hailThreshold,
                thresholdRuleCitation: rule, functionalDamageExceedsThreshold: qualifies, verdict: verdict,
                verdictReasoning: reasoning, stormAttributable: anyDamage, nonStormDamageObserved: nonStormObs(data))

        case .metal:
            let exceedsDent = data.metalDentedPanelsPercent > HaagThresholds.metalDentedPanelPercentThreshold
            let hasSeamDisengagement = data.seamDisengagementCount > 0
            let qualifies = exceedsDent || hasSeamDisengagement
            let verdict: SlopeVerdict = qualifies ? .fullReplacement : (data.metalDentsFunctionalCount > 0 ? .repair : .noDamage)
            let reasoning = "Functional dents: \(data.metalDentsFunctionalCount); panel%=\(pct(data.metalDentedPanelsPercent)) vs 25%; seam disengagement: \(data.seamDisengagementCount); cosmetic dents (noted only): \(data.metalDentsCosmeticCount)"

            return HaagSlopeVerdict(
                slopeId: data.slopeId, hitsInTestSquare: data.metalDentsFunctionalCount, threshold: nil,
                thresholdRuleCitation: rule, functionalDamageExceedsThreshold: qualifies, verdict: verdict,
                verdictReasoning: reasoning,
                stormAttributable: data.metalDentsFunctionalCount + data.seamDisengagementCount > 0,
                nonStormDamageObserved: nonStormObs(data))

        case .tile, .slate:
            let exceedsSlope = data.tilesBrokenPercent > HaagThresholds.tileBrokenPercentThreshold
            let qualifies = exceedsSlope || data.underlaymentExposureCount > 0
            let verdict: SlopeVerdict = qualifies ? .fullReplacement : (data.tilesBrokenCount > 0 ? .repair : .noDamage)
            let reasoning = "Broken/cracked units: \(data.tilesBrokenCount); broken%=\(pct(data.tilesBrokenPercent)) vs 10%; underlayment exposures: \(data.underlaymentExposureCount)"

            return HaagSlopeVerdict(
                slopeId: data.slopeId, hitsInTestSquare: data.tilesBrokenCount, threshold: nil,
                thresholdRuleCitation: rule, functionalDamageExceedsThreshold: qualifies, verdict: verdict,
                verdictReasoning: reasoning,
                stormAttributable: data.tilesBrokenCount + data.underlaymentExposureCount > 0,
                nonStormDamageObserved: nonStormObs(data))

        case .wood:
            let exceedsHits = data.hailHitsTotal > HaagThresholds.woodShakeHitsThreshold
            // missingShinglesCount doubles as the broken-shake proxy for wood.
            let exceedsBroken = data.missingShinglesCount >= HaagThresholds.woodShakeBrokenThreshold
            let qualifies = exceedsHits || exceedsBroken
            let anyDamage = data.hailHitsTotal + data.missingShinglesCount > 0
            let verdict: SlopeVerdict = qualifies ? .fullReplacement : (anyDamage ? .repair : .noDamage)
            let reasoning = "Hits: \(data.hailHitsTotal) vs \(HaagThresholds.woodShakeHitsThreshold); broken shakes: \(data.missingShinglesCount) vs \(HaagThresholds.woodShakeBrokenThreshold)"

            return HaagSlopeVerdict(
                slopeId: data.slopeId, hitsInTestSquare: data.hailHitsTotal, threshold: HaagThresholds.woodShakeHitsThreshold,
                thresholdRuleCitation: rule, functionalDamageExceedsThreshold: qualifies, verdict: verdict,
                verdictReasoning: reasoning, stormAttributable: anyDamage, nonStormDamageObserved: nonStormObs(data))

        case .commercialFlat:
            let punctures = Int(data.puncturesPerHundredSqFt.rounded())
            let exceeds = punctures > HaagThresholds.commercialFlatPunctureDensityThreshold
            let qualifies = exceeds || data.adhesionFailureAreaSqFt > 0
            let verdict: SlopeVerdict = qualifies ? .fullReplacement : (data.puncturesPerHundredSqFt > 0 ? .repair : .noDamage)
            let reasoning = "Punctures/100sf: \(punctures) vs \(HaagThresholds.commercialFlatPunctureDensityThreshold); adhesion failure observations: \(Int(data.adhesionFailureAreaSqFt.rounded()))"

            return HaagSlopeVerdict(
                slopeId: data.slopeId, hitsInTestSquare: punctures, threshold: HaagThresholds.commercialFlatPunctureDensityThreshold,
                thresholdRuleCitation: rule, functionalDamageExceedsThreshold: qualifies, verdict: verdict,
                verdictReasoning: reasoning, stormAttributable: punctures > 0, nonStormDamageObserved: nonStormObs(data))

        case .unknown:
            return HaagSlopeVerdict(
                slopeId: data.slopeId, hitsInTestSquare: 0, threshold: nil, thresholdRuleCitation: rule,
                functionalDamageExceedsThreshold: false, verdict: .noDamage,
                verdictReasoning: "Material unidentified — manual inspector judgment required.",
                stormAttributable: false, nonStormDamageObserved: nonStormObs(data))
        }
    }

    // MARK: - Helpers

    private static func nonStormObs(_ d: SlopeAggregateData) -> [String] {
        var obs: [String] = []
        if d.blistersCount > 0 { obs.append("Thermal blisters (\(d.blistersCount)) — heat-related, not storm-attributable") }
        if d.algaeMossCount > 0 { obs.append("Algae / moss (\(d.algaeMossCount)) — organic growth, not storm-attributable") }
        if d.footfallDamageCount > 0 { obs.append("Footfall damage (\(d.footfallDamageCount)) — foot traffic, not storm-attributable") }
        if d.metalDentsCosmeticCount > 0 { obs.append("Cosmetic metal dents (\(d.metalDentsCosmeticCount)) — noted only, below functional threshold") }
        return obs
    }

    private static func worst(_ current: ForensicSeverity?, _ next: ForensicSeverity) -> ForensicSeverity {
        guard let current else { return next }
        let order: [ForensicSeverity] = [.minor, .moderate, .severe]
        let a = order.firstIndex(of: current) ?? 0
        let b = order.firstIndex(of: next) ?? 0
        return order[max(a, b)]
    }

    private static func matTransfer(from severity: ForensicSeverity?) -> MatTransferSeverity {
        switch severity {
        case .none: return .none
        case .minor: return .light
        case .moderate: return .moderate
        case .severe: return .severe
        }
    }

    private static func granule(from severity: ForensicSeverity?) -> GranuleLossLevel {
        switch severity {
        case .none: return .none
        case .minor: return .light
        case .moderate: return .moderate
        case .severe: return .severe
        }
    }

    private static func pct(_ value: Double) -> String {
        String(format: "%.1f", value * 100)
    }
}
