import Foundation

// MARK: - DecisionEngine
//
// Thin adapter over `HaagDecisionEngine`. Takes an Inspection, evaluates it
// against published Haag thresholds via the rigorous engine, then maps the
// per-slope + roof-level decision back onto the editable `Slope`/`Summary`
// boolean contract the rest of the app (and the PDF report) reads from.
//
// Keeping a single engine behind this façade guarantees the in-app verdicts
// and the generated HAAG report always agree. Pure function — no I/O.

nonisolated enum DecisionEngine {

    /// Evaluates every slope against the HAAG engine for the roof's covering,
    /// then rebuilds the roof-level summary. The returned Inspection is a fully
    /// scored copy of the input.
    static func decide(_ inspection: Inspection) -> Inspection {
        var insp = inspection

        let decision = HaagDecisionEngine.evaluate(.from(insp))
        let byId: [String: HaagSlopeDecision] = Dictionary(
            decision.slopeDecisions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // MARK: Per-slope mapping

        insp.slopes = insp.slopes.map { slope in
            var s = slope
            let hail = s.damageTypes.hail
            let wind = s.damageTypes.wind
            let anyRawDamage = (hail.asphaltBruise
                + hail.asphaltMatFracture
                + hail.asphaltGranuleLossExposed
                + wind.shingleCrease
                + wind.shingleMissing
                + wind.shingleLiftedUnsealed) > 0

            let rec = byId[s.orientation]?.recommendation
            let replacement = rec == .replace
            let repairs = rec == .repair
            s.slopeReplacementRecommended = replacement
            s.slopeRepairsRecommended = repairs
            s.functionalDamagePresent = replacement || repairs
            s.cosmeticOnly = !s.functionalDamagePresent && anyRawDamage
            // Flag-gated elsewhere; never set true by the deterministic engine.
            s.verifyWithInspector = false
            return s
        }

        // MARK: Roof-level summary mapping

        let replacements = insp.slopes.filter { $0.slopeReplacementRecommended }
        insp.summary.roofAnyFunctionalDamage = insp.slopes.contains { $0.functionalDamagePresent }
        insp.summary.roofFullReplacementRecommended = decision.overallRecommendation == .fullReplacement
        insp.summary.roofPartialReplacementRecommended = decision.overallRecommendation == .partialReplacement
        insp.summary.roofRepairsRecommended = decision.overallRecommendation == .repair
        insp.summary.replacementSlopesList = replacements
            .map(\.orientation)
            .joined(separator: ", ")

        return insp
    }
}
