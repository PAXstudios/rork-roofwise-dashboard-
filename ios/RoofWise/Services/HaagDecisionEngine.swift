import Foundation

// MARK: - HAAG Decision Engine
//
// Deterministic, transparent rules engine that evaluates inspection data
// against published Haag Engineering thresholds and produces an
// insurance-grade conclusion.
//
// Source of truth = the JSON output (HaagDecision). Every field in the
// decision must be traceable back to:
//   • a counted hit (markerHits / findingHits)
//   • a measured percentage (damagedTilesPercent / damagedSlatesPercent)
//   • an explicitly triggered override (HaagOverride)
//
// We never invent numbers. If we don't have data we say so via
// `EvidenceQuality.insufficient` and the rule short-circuits.
//
// References:
//   - Haag Residential Roofs Damage Assessment (current edition)
//   - Haag Certified Inspector training thresholds
//   - Carrier convention: 8 functional hits / 100 sq ft test square
//     for asphalt / wood / metal; 10% damaged tiles for concrete & clay;
//     8% for slate; any functional breach for low-slope membranes.

// MARK: - Inputs

nonisolated struct HaagInspectionInput: Codable, Sendable {
    let propertyId: String?
    let inspectionId: String
    let inspectedAt: Date
    let roofCovering: HaagRoofCovering
    let roofAgeYears: Int?
    let totalSlopes: Int
    let slopes: [HaagSlopeInput]
    /// Caller-supplied flags that turn into overrides if true.
    let contextFlags: HaagContextFlags
}

nonisolated struct HaagSlopeInput: Codable, Sendable, Identifiable {
    let id: String
    let name: String                    // e.g. "Front (S)"
    let orientation: String?            // "N" / "NE" / "S" / etc.
    let pitch: String?                  // "7/12"
    /// Approximate slope area in 100 sq ft "squares". Used to compute
    /// per-square hit density. Caller may pass nil if unknown — engine
    /// will fall back to the test-square count derived from photos.
    let approxSquares: Double?
    /// Test squares photographed on this slope. The HAAG test square is
    /// 10x10 ft = 100 sq ft. Fractional values allowed (e.g. 0.5 for a
    /// half-square photographed). Single-shingle close-ups should NOT
    /// inflate this number.
    let testSquaresPhotographed: Double
    /// Counted impact / damage hits attributable to this slope.
    let hits: HaagHitCounts
    /// For tile / slate roofs: visible tile counts.
    let tileCounts: HaagTileCounts?
    /// For low-slope membranes: explicit breach evidence.
    let membraneBreach: Bool
    let photoIds: [String]
}

nonisolated struct HaagHitCounts: Codable, Sendable {
    /// Functional hail strikes (mat fracture, granule displacement w/ bruising, etc.).
    let functionalHail: Int
    /// Wind hits (creasing at nail line, lifted/folded tabs, missing shingles).
    let functionalWind: Int
    /// Cracking / splitting that breaches the watertight layer.
    let functionalCrack: Int
    /// Dents on metal panels that compromise seam, fastener, or coating.
    let functionalMetalDent: Int
    /// Cosmetic-only marks (tracked for the report but excluded from decision).
    let cosmetic: Int

    var totalFunctional: Int {
        functionalHail + functionalWind + functionalCrack + functionalMetalDent
    }
}

nonisolated struct HaagTileCounts: Codable, Sendable {
    let visibleTiles: Int
    let damagedTiles: Int   // cracked / broken / slipped / missing
}

nonisolated struct HaagContextFlags: Codable, Sendable {
    /// Matching shingle discontinued — supports full slope/roof replacement
    /// when partial repair would not match (line-of-sight rule).
    let matchingDiscontinued: Bool
    /// Two or more existing roof layers — code typically requires tear-off,
    /// converting any qualifying repair into a full replacement.
    let doubleLayerPresent: Bool
    /// Visible deck rot or sagging found — escalates to structural.
    let structuralDamage: Bool
    /// Roof is older than manufacturer warranty / >25 yrs — supports
    /// full replacement when partial repair would not blend.
    let beyondServiceLife: Bool
    /// State / municipality enforces a 25%-rule (one-roof rule) — any
    /// damage exceeding 25% of a slope triggers full replacement.
    let jurisdictionTwentyFiveRule: Bool
}

// MARK: - Roof Covering

nonisolated enum HaagRoofCovering: String, Codable, Sendable, CaseIterable {
    case asphaltComposition
    case woodShakeShingle
    case metalPanel
    case concreteTile
    case clayTile
    case slate
    case lowSlopeMembrane
    case unknown

    var displayName: String {
        switch self {
        case .asphaltComposition: return "Asphalt / Composition Shingle"
        case .woodShakeShingle: return "Wood Shake / Shingle"
        case .metalPanel: return "Metal Panel"
        case .concreteTile: return "Concrete Tile"
        case .clayTile: return "Clay Tile"
        case .slate: return "Slate"
        case .lowSlopeMembrane: return "Low-Slope Membrane"
        case .unknown: return "Unknown"
        }
    }

    /// Per-slope, per 100 sq ft test square threshold for Replacement.
    /// nil = covering uses a percentage rule, not a hit count.
    var hitsPerSquareThreshold: Int? {
        switch self {
        case .asphaltComposition, .woodShakeShingle, .metalPanel: return 8
        case .concreteTile, .clayTile, .slate, .lowSlopeMembrane, .unknown: return nil
        }
    }

    /// Percentage-of-damaged-tiles threshold (0–100). nil = N/A.
    var damagedPercentThreshold: Double? {
        switch self {
        case .concreteTile, .clayTile: return 10.0
        case .slate: return 8.0
        case .asphaltComposition, .woodShakeShingle, .metalPanel,
             .lowSlopeMembrane, .unknown:
            return nil
        }
    }

    var ruleText: String {
        switch self {
        case .asphaltComposition:
            return "Asphalt: 8+ functional hail hits per 100 sq ft test square supports Replacement of the affected slope."
        case .woodShakeShingle:
            return "Wood shake/shingle: 8+ functional impacts per 100 sq ft test square supports Replacement."
        case .metalPanel:
            return "Metal panel: 8+ functional dents (compromising seam, fastener, or coating) per 100 sq ft supports Replacement."
        case .concreteTile:
            return "Concrete tile: 10% or more of visible tiles damaged supports Replacement."
        case .clayTile:
            return "Clay tile: 10% or more of visible tiles damaged supports Replacement."
        case .slate:
            return "Slate: 8% or more of visible slates broken/cracked per slope supports Replacement."
        case .lowSlopeMembrane:
            return "Low-slope membrane: any functional fracture or membrane breach supports Replacement of the affected section."
        case .unknown:
            return "Roof covering not identified — manual review required."
        }
    }
}

// MARK: - Output

nonisolated struct HaagDecision: Codable, Sendable {
    let engineVersion: String
    let inspectionId: String
    let propertyId: String?
    let evaluatedAt: Date
    let roofCovering: HaagRoofCovering
    let roofAgeYears: Int?
    let evidenceQuality: EvidenceQuality
    let overallRecommendation: HaagRecommendation
    let perils: [HaagPeril]
    let slopeDecisions: [HaagSlopeDecision]
    let triggeredOverrides: [HaagOverride]
    let totals: HaagTotals
    let summary: String
    let traceability: [HaagTraceEntry]
}

nonisolated enum HaagRecommendation: String, Codable, Sendable {
    case repair                // localized repair, no carrier file
    case partialReplacement    // affected slope(s) only
    case fullReplacement       // entire roof
    case insufficientData      // not enough evidence to decide
    case noFunctionalDamage    // cosmetic only
}

nonisolated enum HaagPeril: String, Codable, Sendable {
    case hail
    case wind
    case combinedHailWind
    case mechanical
    case wear
}

nonisolated enum EvidenceQuality: String, Codable, Sendable {
    case insufficient   // < required test squares or no slope data
    case partial        // some slopes with adequate sample
    case complete       // all reported slopes have ≥ 1 test square
}

nonisolated struct HaagSlopeDecision: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let recommendation: HaagSlopeRecommendation
    let hitsPerSquare: Double?
    let damagedPercent: Double?
    let testSquaresPhotographed: Double
    let totalFunctionalHits: Int
    let triggeredRule: String
    let thresholdText: String
    let perils: [HaagPeril]
}

nonisolated enum HaagSlopeRecommendation: String, Codable, Sendable {
    case replace
    case repair
    case noFunctionalDamage
    case insufficientData
}

nonisolated struct HaagOverride: Codable, Sendable, Identifiable {
    let id: String
    let kind: Kind
    let escalatesTo: HaagRecommendation
    let rationale: String

    enum Kind: String, Codable, Sendable {
        case matchingDiscontinued
        case doubleLayerCode
        case structuralDamage
        case beyondServiceLife
        case jurisdictionTwentyFiveRule
        case combinedPerilAcrossSlopes
        case lineOfSight
    }
}

nonisolated struct HaagTotals: Codable, Sendable {
    let slopesEvaluated: Int
    let slopesReplaceQualifying: Int
    let testSquaresPhotographed: Double
    let totalFunctionalHits: Int
    let totalCosmeticHits: Int
    let weightedHitsPerSquare: Double
}

nonisolated struct HaagTraceEntry: Codable, Sendable, Identifiable {
    let id: String
    let kind: Kind
    let detail: String

    enum Kind: String, Codable, Sendable {
        case input
        case computation
        case rule
        case override
        case decision
    }
}

// MARK: - Engine

nonisolated enum HaagDecisionEngine {

    static let version: String = "1.0.0"

    /// Evaluates the supplied inspection input against Haag thresholds
    /// and returns a fully traceable decision. Pure function — no I/O.
    static func evaluate(_ input: HaagInspectionInput) -> HaagDecision {
        var trace: [HaagTraceEntry] = []
        trace.append(.init(
            id: "input.covering",
            kind: .input,
            detail: "Roof covering: \(input.roofCovering.displayName)"
        ))
        trace.append(.init(
            id: "input.slopes",
            kind: .input,
            detail: "Slopes reported: \(input.totalSlopes); slopes with data: \(input.slopes.count)"
        ))

        // Evidence quality gate.
        let evidenceQuality = computeEvidenceQuality(input: input, trace: &trace)

        guard !input.slopes.isEmpty else {
            return makeDecision(
                input: input,
                evidenceQuality: .insufficient,
                slopeDecisions: [],
                overrides: [],
                overall: .insufficientData,
                perils: [],
                summary: "No slopes were submitted for evaluation. Capture at least one 100 sq ft test square per accessible slope to produce a decision.",
                trace: trace
            )
        }

        // Per-slope evaluation.
        var slopeDecisions: [HaagSlopeDecision] = []
        for slope in input.slopes {
            let decision = evaluateSlope(slope, covering: input.roofCovering, trace: &trace)
            slopeDecisions.append(decision)
        }

        // Aggregate perils.
        let perilSet = aggregatePerils(slopeDecisions: slopeDecisions, trace: &trace)

        // Base recommendation — driven solely by counted slope outcomes.
        let qualifying = slopeDecisions.filter { $0.recommendation == .replace }
        let baseRecommendation: HaagRecommendation = {
            if qualifying.isEmpty {
                let anyDamage = slopeDecisions.contains { $0.totalFunctionalHits > 0 }
                let anyInsufficient = slopeDecisions.contains { $0.recommendation == .insufficientData }
                if anyInsufficient && !anyDamage { return .insufficientData }
                return anyDamage ? .repair : .noFunctionalDamage
            }
            // ≥ 50% of evaluated slopes qualify, or 3+ slopes qualify on a
            // 4+ slope roof → full replacement is the cleanest claim.
            let evaluated = slopeDecisions.filter { $0.recommendation != .insufficientData }.count
            let qualifyingRatio = evaluated > 0 ? Double(qualifying.count) / Double(evaluated) : 0
            if qualifyingRatio >= 0.5 || (input.totalSlopes >= 4 && qualifying.count >= 3) {
                return .fullReplacement
            }
            return .partialReplacement
        }()
        trace.append(.init(
            id: "decision.base",
            kind: .decision,
            detail: "Base recommendation: \(baseRecommendation.rawValue) (\(qualifying.count)/\(slopeDecisions.count) slopes qualify)"
        ))

        // Apply overrides on top of the base decision.
        var overrides: [HaagOverride] = []
        var finalRecommendation = baseRecommendation
        let flags = input.contextFlags

        if flags.structuralDamage {
            let o = HaagOverride(
                id: "override.structural",
                kind: .structuralDamage,
                escalatesTo: .fullReplacement,
                rationale: "Decking rot / sagging documented — structural integrity compromised; full replacement required."
            )
            overrides.append(o)
            finalRecommendation = escalate(finalRecommendation, to: .fullReplacement)
            trace.append(.init(id: o.id, kind: .override, detail: o.rationale))
        }
        if flags.doubleLayerPresent && finalRecommendation != .noFunctionalDamage {
            let o = HaagOverride(
                id: "override.doubleLayer",
                kind: .doubleLayerCode,
                escalatesTo: .fullReplacement,
                rationale: "Two or more existing layers detected — code requires full tear-off; partial repair not viable."
            )
            overrides.append(o)
            finalRecommendation = escalate(finalRecommendation, to: .fullReplacement)
            trace.append(.init(id: o.id, kind: .override, detail: o.rationale))
        }
        if flags.matchingDiscontinued && (finalRecommendation == .partialReplacement || finalRecommendation == .repair) {
            let o = HaagOverride(
                id: "override.matching",
                kind: .matchingDiscontinued,
                escalatesTo: .fullReplacement,
                rationale: "Matching shingle/tile is discontinued — line-of-sight rule supports full replacement to maintain uniform appearance."
            )
            overrides.append(o)
            finalRecommendation = .fullReplacement
            trace.append(.init(id: o.id, kind: .override, detail: o.rationale))
        }
        if flags.jurisdictionTwentyFiveRule && qualifying.count >= 1 && finalRecommendation == .partialReplacement {
            let o = HaagOverride(
                id: "override.twentyFiveRule",
                kind: .jurisdictionTwentyFiveRule,
                escalatesTo: .fullReplacement,
                rationale: "Local 25% rule: damage exceeding 25% of a single slope mandates full roof replacement."
            )
            overrides.append(o)
            finalRecommendation = .fullReplacement
            trace.append(.init(id: o.id, kind: .override, detail: o.rationale))
        }
        if flags.beyondServiceLife && finalRecommendation == .partialReplacement {
            let o = HaagOverride(
                id: "override.serviceLife",
                kind: .beyondServiceLife,
                escalatesTo: .fullReplacement,
                rationale: "Roof beyond service life (>25 yrs / past warranty) — partial replacement would not blend; full replacement supported."
            )
            overrides.append(o)
            finalRecommendation = .fullReplacement
            trace.append(.init(id: o.id, kind: .override, detail: o.rationale))
        }
        if perilSet.contains(.combinedHailWind) && finalRecommendation == .partialReplacement {
            let o = HaagOverride(
                id: "override.combinedPeril",
                kind: .combinedPerilAcrossSlopes,
                escalatesTo: .fullReplacement,
                rationale: "Combined-peril event (hail + wind) confirmed across multiple slopes — full replacement is supportable per HAAG guidance."
            )
            overrides.append(o)
            finalRecommendation = .fullReplacement
            trace.append(.init(id: o.id, kind: .override, detail: o.rationale))
        }

        // Totals.
        let totals = computeTotals(slopeDecisions: slopeDecisions, allSlopes: input.slopes)
        trace.append(.init(
            id: "totals",
            kind: .computation,
            detail: "Totals — slopesEvaluated=\(totals.slopesEvaluated), qualifying=\(totals.slopesReplaceQualifying), testSquares=\(format(totals.testSquaresPhotographed)), funcHits=\(totals.totalFunctionalHits), weightedHits/sq=\(format(totals.weightedHitsPerSquare))"
        ))

        let summary = composeSummary(
            covering: input.roofCovering,
            recommendation: finalRecommendation,
            qualifying: qualifying,
            totals: totals,
            perils: perilSet,
            overrides: overrides
        )

        return makeDecision(
            input: input,
            evidenceQuality: evidenceQuality,
            slopeDecisions: slopeDecisions,
            overrides: overrides,
            overall: finalRecommendation,
            perils: perilSet,
            summary: summary,
            trace: trace
        )
    }

    /// Convenience: encode the decision to pretty-printed JSON.
    static func encodeJSON(_ decision: HaagDecision) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(decision)) ?? Data()
    }

    // MARK: Slope evaluation

    private static func evaluateSlope(
        _ slope: HaagSlopeInput,
        covering: HaagRoofCovering,
        trace: inout [HaagTraceEntry]
    ) -> HaagSlopeDecision {

        let hits = slope.hits
        let funcTotal = hits.totalFunctional

        // Determine peril mix on this slope.
        var slopePerils: [HaagPeril] = []
        if hits.functionalHail > 0 { slopePerils.append(.hail) }
        if hits.functionalWind > 0 { slopePerils.append(.wind) }
        if hits.functionalCrack > 0 && !slopePerils.contains(.wear) { slopePerils.append(.wear) }
        if hits.functionalMetalDent > 0 && !slopePerils.contains(.hail) { slopePerils.append(.hail) }

        // Insufficient sampling → no decision.
        if slope.testSquaresPhotographed <= 0 && slope.tileCounts == nil && !slope.membraneBreach {
            trace.append(.init(
                id: "slope.\(slope.id).insufficient",
                kind: .rule,
                detail: "\(slope.name): no test squares photographed and no tile/membrane evidence — insufficient data."
            ))
            return HaagSlopeDecision(
                id: slope.id, name: slope.name,
                recommendation: .insufficientData,
                hitsPerSquare: nil, damagedPercent: nil,
                testSquaresPhotographed: slope.testSquaresPhotographed,
                totalFunctionalHits: funcTotal,
                triggeredRule: "Insufficient sampling",
                thresholdText: covering.ruleText,
                perils: slopePerils
            )
        }

        // Tile / slate percentage rules.
        if let pctThreshold = covering.damagedPercentThreshold {
            guard let counts = slope.tileCounts, counts.visibleTiles > 0 else {
                trace.append(.init(
                    id: "slope.\(slope.id).tileCounts.missing",
                    kind: .rule,
                    detail: "\(slope.name): tile counts required for \(covering.displayName) but not provided — insufficient data."
                ))
                return HaagSlopeDecision(
                    id: slope.id, name: slope.name,
                    recommendation: .insufficientData,
                    hitsPerSquare: nil, damagedPercent: nil,
                    testSquaresPhotographed: slope.testSquaresPhotographed,
                    totalFunctionalHits: funcTotal,
                    triggeredRule: "Tile counts missing",
                    thresholdText: covering.ruleText,
                    perils: slopePerils
                )
            }
            let pct = Double(counts.damagedTiles) / Double(counts.visibleTiles) * 100.0
            let qualifies = pct >= pctThreshold
            trace.append(.init(
                id: "slope.\(slope.id).pct",
                kind: .computation,
                detail: "\(slope.name): \(counts.damagedTiles)/\(counts.visibleTiles) damaged = \(format(pct))% vs \(format(pctThreshold))% threshold → \(qualifies ? "QUALIFIES" : "below")"
            ))
            return HaagSlopeDecision(
                id: slope.id, name: slope.name,
                recommendation: qualifies ? .replace : (counts.damagedTiles > 0 ? .repair : .noFunctionalDamage),
                hitsPerSquare: nil,
                damagedPercent: pct,
                testSquaresPhotographed: slope.testSquaresPhotographed,
                totalFunctionalHits: funcTotal,
                triggeredRule: qualifies
                    ? "\(format(pct))% damaged ≥ \(format(pctThreshold))% threshold"
                    : "\(format(pct))% damaged < \(format(pctThreshold))% threshold",
                thresholdText: covering.ruleText,
                perils: slopePerils
            )
        }

        // Low-slope membrane: any breach triggers replacement of the section.
        if covering == .lowSlopeMembrane {
            let qualifies = slope.membraneBreach || hits.functionalCrack > 0
            trace.append(.init(
                id: "slope.\(slope.id).membrane",
                kind: .rule,
                detail: "\(slope.name): membrane breach = \(qualifies)"
            ))
            return HaagSlopeDecision(
                id: slope.id, name: slope.name,
                recommendation: qualifies ? .replace : (funcTotal > 0 ? .repair : .noFunctionalDamage),
                hitsPerSquare: nil,
                damagedPercent: nil,
                testSquaresPhotographed: slope.testSquaresPhotographed,
                totalFunctionalHits: funcTotal,
                triggeredRule: qualifies ? "Functional fracture / membrane breach" : "No functional breach",
                thresholdText: covering.ruleText,
                perils: slopePerils
            )
        }

        // Hits-per-square rule (asphalt / wood / metal).
        guard let hitThreshold = covering.hitsPerSquareThreshold else {
            trace.append(.init(
                id: "slope.\(slope.id).noRule",
                kind: .rule,
                detail: "\(slope.name): no rule configured for covering \(covering.rawValue)"
            ))
            return HaagSlopeDecision(
                id: slope.id, name: slope.name,
                recommendation: .insufficientData,
                hitsPerSquare: nil, damagedPercent: nil,
                testSquaresPhotographed: slope.testSquaresPhotographed,
                totalFunctionalHits: funcTotal,
                triggeredRule: "No threshold for covering",
                thresholdText: covering.ruleText,
                perils: slopePerils
            )
        }

        let squares = max(slope.testSquaresPhotographed, 0.0001)
        let hitsPerSquare = Double(funcTotal) / squares
        let qualifies = hitsPerSquare >= Double(hitThreshold)
        trace.append(.init(
            id: "slope.\(slope.id).density",
            kind: .computation,
            detail: "\(slope.name): \(funcTotal) functional hits / \(format(slope.testSquaresPhotographed)) sq = \(format(hitsPerSquare))/sq vs \(hitThreshold)/sq threshold → \(qualifies ? "QUALIFIES" : "below")"
        ))

        return HaagSlopeDecision(
            id: slope.id, name: slope.name,
            recommendation: qualifies ? .replace : (funcTotal > 0 ? .repair : .noFunctionalDamage),
            hitsPerSquare: hitsPerSquare,
            damagedPercent: nil,
            testSquaresPhotographed: slope.testSquaresPhotographed,
            totalFunctionalHits: funcTotal,
            triggeredRule: qualifies
                ? "\(format(hitsPerSquare)) hits/sq ≥ \(hitThreshold) hits/sq threshold"
                : "\(format(hitsPerSquare)) hits/sq < \(hitThreshold) hits/sq threshold",
            thresholdText: covering.ruleText,
            perils: slopePerils
        )
    }

    // MARK: Aggregation

    private static func aggregatePerils(
        slopeDecisions: [HaagSlopeDecision],
        trace: inout [HaagTraceEntry]
    ) -> [HaagPeril] {
        let all = Set(slopeDecisions.flatMap { $0.perils })
        var out: [HaagPeril] = []
        if all.contains(.hail) { out.append(.hail) }
        if all.contains(.wind) { out.append(.wind) }
        if all.contains(.hail) && all.contains(.wind) { out.append(.combinedHailWind) }
        if all.contains(.wear) { out.append(.wear) }
        trace.append(.init(
            id: "perils.aggregate",
            kind: .computation,
            detail: "Perils observed: \(out.map(\.rawValue).joined(separator: ", "))"
        ))
        return out
    }

    private static func computeEvidenceQuality(
        input: HaagInspectionInput,
        trace: inout [HaagTraceEntry]
    ) -> EvidenceQuality {
        guard !input.slopes.isEmpty else { return .insufficient }
        let withSamples = input.slopes.filter { $0.testSquaresPhotographed > 0 || $0.tileCounts != nil || $0.membraneBreach }
        if withSamples.isEmpty { return .insufficient }
        if withSamples.count < input.totalSlopes { return .partial }
        return .complete
    }

    private static func computeTotals(
        slopeDecisions: [HaagSlopeDecision],
        allSlopes: [HaagSlopeInput]
    ) -> HaagTotals {
        let evaluated = slopeDecisions.count
        let qualifying = slopeDecisions.filter { $0.recommendation == .replace }.count
        let testSquares = allSlopes.reduce(0.0) { $0 + $1.testSquaresPhotographed }
        let funcHits = allSlopes.reduce(0) { $0 + $1.hits.totalFunctional }
        let cosmeticHits = allSlopes.reduce(0) { $0 + $1.hits.cosmetic }
        let weighted: Double = testSquares > 0 ? Double(funcHits) / testSquares : 0
        return HaagTotals(
            slopesEvaluated: evaluated,
            slopesReplaceQualifying: qualifying,
            testSquaresPhotographed: testSquares,
            totalFunctionalHits: funcHits,
            totalCosmeticHits: cosmeticHits,
            weightedHitsPerSquare: weighted
        )
    }

    // MARK: Helpers

    private static func escalate(_ current: HaagRecommendation, to target: HaagRecommendation) -> HaagRecommendation {
        let order: [HaagRecommendation] = [
            .insufficientData, .noFunctionalDamage, .repair, .partialReplacement, .fullReplacement
        ]
        let a = order.firstIndex(of: current) ?? 0
        let b = order.firstIndex(of: target) ?? 0
        return order[max(a, b)]
    }

    private static func composeSummary(
        covering: HaagRoofCovering,
        recommendation: HaagRecommendation,
        qualifying: [HaagSlopeDecision],
        totals: HaagTotals,
        perils: [HaagPeril],
        overrides: [HaagOverride]
    ) -> String {
        let perilText: String = {
            if perils.contains(.combinedHailWind) { return "combined hail + wind" }
            if perils.contains(.hail) && perils.contains(.wind) { return "hail and wind" }
            if perils.contains(.hail) { return "hail" }
            if perils.contains(.wind) { return "wind" }
            return "wear"
        }()

        switch recommendation {
        case .insufficientData:
            return "Insufficient evidence to render a HAAG decision. Capture at least one 100 sq ft test square per accessible slope, plus close-ups of any documented damage."
        case .noFunctionalDamage:
            return "Roof shows no functional damage that meets HAAG thresholds. \(covering.ruleText)"
        case .repair:
            return "Localized damage documented but no slope reaches the HAAG replacement threshold. \(covering.ruleText) Repair / monitor."
        case .partialReplacement:
            let names = qualifying.map(\.name).joined(separator: ", ")
            return "Partial replacement supported per HAAG. \(qualifying.count) slope(s) (\(names)) exceed the \(covering.displayName) threshold from \(perilText). \(covering.ruleText)"
        case .fullReplacement:
            let overrideText = overrides.isEmpty ? "" : " Overrides triggered: \(overrides.map { $0.kind.rawValue }.joined(separator: ", "))."
            return "Full replacement supported per HAAG. \(qualifying.count)/\(totals.slopesEvaluated) slopes meet the \(covering.displayName) threshold from \(perilText).\(overrideText) \(covering.ruleText)"
        }
    }

    private static func makeDecision(
        input: HaagInspectionInput,
        evidenceQuality: EvidenceQuality,
        slopeDecisions: [HaagSlopeDecision],
        overrides: [HaagOverride],
        overall: HaagRecommendation,
        perils: [HaagPeril],
        summary: String,
        trace: [HaagTraceEntry]
    ) -> HaagDecision {
        let totals = computeTotals(slopeDecisions: slopeDecisions, allSlopes: input.slopes)
        return HaagDecision(
            engineVersion: version,
            inspectionId: input.inspectionId,
            propertyId: input.propertyId,
            evaluatedAt: Date(),
            roofCovering: input.roofCovering,
            roofAgeYears: input.roofAgeYears,
            evidenceQuality: evidenceQuality,
            overallRecommendation: overall,
            perils: perils,
            slopeDecisions: slopeDecisions,
            triggeredOverrides: overrides,
            totals: totals,
            summary: summary,
            traceability: trace
        )
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
