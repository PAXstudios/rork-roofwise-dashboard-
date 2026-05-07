import Foundation

// MARK: - DecisionEngine
//
// Pure function. Takes an Inspection, applies Haag-style per-slope rules
// (parameterized by roof.primary_material), then rolls the slopes up
// into Inspection.summary. Never performs I/O.

nonisolated enum DecisionEngine {

    /// Evaluates every slope against the rules for the roof's primary
    /// material, then rebuilds the roof-level summary. The returned
    /// Inspection is a fully scored copy of the input.
    static func decide(_ inspection: Inspection) -> Inspection {
        var insp = inspection
        let material = insp.roof.primaryMaterial
        let layers = insp.roof.layers
        let condition = insp.roof.overallConditionPreStorm

        // MARK: Per-slope rules

        insp.slopes = insp.slopes.map { slope in
            var s = slope
            let hail = s.damageTypes.hail
            let wind = s.damageTypes.wind
            let totalHail = hail.asphaltBruise
                          + hail.asphaltMatFracture
                          + hail.asphaltGranuleLossExposed
            let testSquares = max(1, s.testSquareCount)
            let hitsPerSquare = Double(totalHail) / Double(testSquares)

            var replacement = false

            switch material {
            case .asphaltShingle:
                if hitsPerSquare >= 8
                    || wind.shingleCrease >= 3
                    || wind.shingleMissing >= 1 {
                    replacement = true
                }
            case .threeTabAsphalt:
                // 3-tab is more vulnerable — drop the threshold to 5.
                if hitsPerSquare >= 5
                    || wind.shingleCrease >= 3
                    || wind.shingleMissing >= 1 {
                    replacement = true
                }
            case .metalPanel:
                // Treat hail bruise count as dent count; estimate panels at
                // 5 per square. Replace when ≥ 25% of panels are dented.
                let totalPanels = max(1.0, s.areaSquares * 5.0)
                let dentPct = Double(totalHail) / totalPanels * 100.0
                if dentPct >= 25 { replacement = true }
            case .woodShake:
                if hitsPerSquare >= 5 || wind.shingleMissing >= 3 {
                    replacement = true
                }
            case .concreteTile:
                // ~100 tiles per square as a working estimate.
                let totalTiles = max(1.0, s.areaSquares * 100.0)
                let pct = Double(totalHail) / totalTiles * 100.0
                if pct >= 10 { replacement = true }
            case .clayTile:
                // Clay shatters on first impact — any broken tile = replace.
                if totalHail >= 1 { replacement = true }
            }

            let anyHailWind = totalHail > 0
                || wind.shingleCrease > 0
                || wind.shingleMissing > 0
                || wind.shingleLiftedUnsealed > 0

            // Aggravators: 2+ layers OR poor pre-storm condition push any
            // functional damage straight to replacement.
            if (layers >= 2 || condition == .poor) && anyHailWind {
                replacement = true
            }

            let repairs = !replacement && anyHailWind

            s.slopeReplacementRecommended = replacement
            s.slopeRepairsRecommended = repairs
            s.functionalDamagePresent = replacement || repairs
            s.cosmeticOnly = !s.functionalDamagePresent && anyHailWind
            return s
        }

        // MARK: Roof-level summary

        let slopes = insp.slopes
        let total = slopes.count
        let replacements = slopes.filter { $0.slopeReplacementRecommended }
        let anyFunctional = slopes.contains { $0.functionalDamagePresent }
        let ratio = total > 0 ? Double(replacements.count) / Double(total) : 0

        let fullReplacement = (ratio > 0.5) || (layers >= 2 && anyFunctional)
        let partialReplacement = !replacements.isEmpty && !fullReplacement
        let repairsOnly = replacements.isEmpty && anyFunctional

        insp.summary.roofAnyFunctionalDamage = anyFunctional
        insp.summary.roofFullReplacementRecommended = fullReplacement
        insp.summary.roofPartialReplacementRecommended = partialReplacement
        insp.summary.roofRepairsRecommended = repairsOnly
        insp.summary.replacementSlopesList = replacements
            .map(\.orientation)
            .joined(separator: ", ")

        return insp
    }
}
