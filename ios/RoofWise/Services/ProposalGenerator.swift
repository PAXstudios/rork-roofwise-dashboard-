import Foundation

/// Pure function. Builds a `Proposal` from an `Inspection` (and an optional
/// origin `CostEstimate`). Drives line items off the DecisionEngine output:
///
/// - full replacement → full set (tear-off + decking + underlayment + …)
/// - partial replacement → per-slope subset for replacement_slopes_list
/// - repairs only → small targeted set (shingle qty + flashing + labor)
nonisolated enum ProposalGenerator {

    // MARK: TX-default unit price table by primary material

    private struct PriceTable {
        let tearOffPerSq: Double
        let deckingPerSq: Double          // per-sq (allowance — ~10% of squares typically)
        let underlaymentPerSq: Double
        let iceWaterPerSq: Double
        let dripEdgePerLF: Double
        let ridgePerLF: Double
        let valleyPerLF: Double
        let shinglesPerSq: Double
        let ventilationPerEa: Double
        let flashingPerLF: Double
        let laborPerSq: Double
    }

    private static func table(for material: RoofPrimaryMaterial) -> PriceTable {
        switch material {
        case .asphaltShingle, .threeTabAsphalt:
            return PriceTable(
                tearOffPerSq: 65, deckingPerSq: 42, underlaymentPerSq: 42,
                iceWaterPerSq: 65, dripEdgePerLF: 4.5, ridgePerLF: 9.5,
                valleyPerLF: 12, shinglesPerSq: 145, ventilationPerEa: 95,
                flashingPerLF: 14, laborPerSq: 110
            )
        case .metalPanel:
            return PriceTable(
                tearOffPerSq: 80, deckingPerSq: 55, underlaymentPerSq: 55,
                iceWaterPerSq: 70, dripEdgePerLF: 6, ridgePerLF: 14,
                valleyPerLF: 18, shinglesPerSq: 850, ventilationPerEa: 140,
                flashingPerLF: 22, laborPerSq: 220
            )
        case .woodShake:
            return PriceTable(
                tearOffPerSq: 95, deckingPerSq: 55, underlaymentPerSq: 50,
                iceWaterPerSq: 65, dripEdgePerLF: 5, ridgePerLF: 12,
                valleyPerLF: 16, shinglesPerSq: 650, ventilationPerEa: 110,
                flashingPerLF: 18, laborPerSq: 180
            )
        case .concreteTile, .clayTile:
            return PriceTable(
                tearOffPerSq: 110, deckingPerSq: 60, underlaymentPerSq: 65,
                iceWaterPerSq: 80, dripEdgePerLF: 7, ridgePerLF: 15,
                valleyPerLF: 22, shinglesPerSq: 950, ventilationPerEa: 165,
                flashingPerLF: 24, laborPerSq: 260
            )
        }
    }

    // MARK: Squares helpers

    private static func totalSquares(_ inspection: Inspection) -> Double {
        if let detected = inspection.roof.detectedAreaSquares, detected > 0 {
            return detected
        }
        let slopeSum = inspection.slopes.reduce(0.0) { $0 + $1.areaSquares }
        return slopeSum > 0 ? slopeSum : 25.0
    }

    private static func replacementSquares(_ inspection: Inspection) -> Double {
        let slopes = inspection.slopes.filter { $0.slopeReplacementRecommended }
        guard !slopes.isEmpty else { return 0 }
        return slopes.reduce(0.0) { $0 + $1.areaSquares }
    }

    // MARK: Public

    static func generate(forInspection inspection: Inspection,
                         costEstimate: CostEstimate? = nil) -> Proposal {
        let summary = inspection.summary
        let material = inspection.roof.primaryMaterial
        let prices = table(for: material)
        let totalSq = totalSquares(inspection)

        var items: [ProposalLineItem] = []

        if summary.roofFullReplacementRecommended {
            items = fullReplacementItems(squares: totalSq, prices: prices)
        } else if summary.roofPartialReplacementRecommended {
            let partialSq = max(replacementSquares(inspection), 1.0)
            items = partialReplacementItems(squares: partialSq,
                                            slopeNames: summary.replacementSlopesList,
                                            prices: prices)
        } else {
            items = repairsOnlyItems(squares: totalSq, prices: prices)
        }

        let scope = scopeNarrative(inspection: inspection, totalSquares: totalSq)
        let originEstimateId = inspection.originEstimateId?.uuidString

        return Proposal(
            originJobId: inspection.id,
            originEstimateId: originEstimateId,
            homeownerName: inspection.job.clientName,
            projectAddress: inspection.job.propertyAddress,
            lineItems: items,
            scopeNarrative: scope
        )
    }

    // MARK: Line item builders

    private static func fullReplacementItems(squares: Double, prices: PriceTable) -> [ProposalLineItem] {
        let sq = squares
        // Decking allowance: 10% of squares as an SF allowance (rounded up).
        let deckingAllowance = max(1.0, (sq * 0.10).rounded())
        // Linear feet rough estimates from squares: perimeter ≈ 4 × √(sq × 100)
        let perimeterLF = max(40, sq.squareRoot() * 40)
        let ridgeLF = max(20, sq * 1.4)
        let valleyLF = max(10, sq * 1.0)
        return [
            .init(kind: .tearOff, quantity: sq, unitPrice: prices.tearOffPerSq),
            .init(kind: .decking, label: "Decking allowance",
                  quantity: deckingAllowance, unit: "sq", unitPrice: prices.deckingPerSq),
            .init(kind: .underlayment, quantity: sq, unitPrice: prices.underlaymentPerSq),
            .init(kind: .iceWaterShield, label: "Ice & Water Shield (eaves)",
                  quantity: max(2, sq * 0.15), unit: "sq", unitPrice: prices.iceWaterPerSq),
            .init(kind: .dripEdge, quantity: perimeterLF, unitPrice: prices.dripEdgePerLF),
            .init(kind: .ridge, quantity: ridgeLF, unitPrice: prices.ridgePerLF),
            .init(kind: .valley, quantity: valleyLF, unitPrice: prices.valleyPerLF),
            .init(kind: .shingles, quantity: sq, unitPrice: prices.shinglesPerSq),
            .init(kind: .ventilation, label: "Ridge / box vents",
                  quantity: max(2, (sq / 6).rounded()), unit: "ea",
                  unitPrice: prices.ventilationPerEa),
            .init(kind: .flashing, quantity: max(20, sq * 0.6),
                  unitPrice: prices.flashingPerLF),
            .init(kind: .labor, label: "Crew labor",
                  quantity: sq, unit: "sq", unitPrice: prices.laborPerSq)
        ]
    }

    private static func partialReplacementItems(squares: Double,
                                                slopeNames: String,
                                                prices: PriceTable) -> [ProposalLineItem] {
        let sq = squares
        let perimeterLF = max(20, sq.squareRoot() * 30)
        return [
            .init(kind: .tearOff,
                  label: slopeNames.isEmpty ? "Tear-off (affected slopes)"
                                            : "Tear-off (\(slopeNames))",
                  quantity: sq, unitPrice: prices.tearOffPerSq),
            .init(kind: .underlayment, quantity: sq, unitPrice: prices.underlaymentPerSq),
            .init(kind: .dripEdge, quantity: perimeterLF, unitPrice: prices.dripEdgePerLF),
            .init(kind: .shingles,
                  label: slopeNames.isEmpty ? "Shingles (affected slopes)"
                                            : "Shingles (\(slopeNames))",
                  quantity: sq, unitPrice: prices.shinglesPerSq),
            .init(kind: .flashing, quantity: max(12, sq * 0.5),
                  unitPrice: prices.flashingPerLF),
            .init(kind: .labor, label: "Crew labor (partial)",
                  quantity: sq, unit: "sq", unitPrice: prices.laborPerSq)
        ]
    }

    private static func repairsOnlyItems(squares: Double, prices: PriceTable) -> [ProposalLineItem] {
        let smallSq = max(0.5, min(2.0, squares * 0.05))
        return [
            .init(kind: .shingles, label: "Replacement shingles (spot repair)",
                  quantity: smallSq, unit: "sq", unitPrice: prices.shinglesPerSq),
            .init(kind: .flashing, label: "Targeted flashing repair",
                  quantity: 12, unit: "lf", unitPrice: prices.flashingPerLF),
            .init(kind: .labor, label: "Repair labor",
                  quantity: 6, unit: "hr", unitPrice: 95)
        ]
    }

    // MARK: Scope

    private static func scopeNarrative(inspection: Inspection, totalSquares sq: Double) -> String {
        let s = inspection.summary
        let mat = inspection.roof.primaryMaterial.displayName
        var lines: [String] = []
        let address = inspection.job.propertyAddress.isEmpty
            ? "the property" : inspection.job.propertyAddress
        lines.append("Scope of work for \(address) — \(mat) roof system, \(String(format: "%.1f", sq)) total squares.")

        if s.roofFullReplacementRecommended {
            lines.append("Complete tear-off and replacement of the existing roof system, including new underlayment, ice & water shield at eaves and valleys, drip edge on all eaves and rakes, ridge and valley material, ventilation upgrades, all step and counter flashing, and new shingles installed to manufacturer specification.")
        } else if s.roofPartialReplacementRecommended {
            let list = s.replacementSlopesList.isEmpty ? "the affected slopes" : s.replacementSlopesList
            lines.append("Partial replacement on \(list). Includes tear-off, underlayment, drip edge, flashing, and shingles on listed slopes only. Adjacent slopes remain in service.")
        } else if s.roofRepairsRecommended {
            lines.append("Targeted repairs to address localized storm damage. Includes spot shingle replacement and flashing repair where needed. No full tear-off.")
        } else {
            lines.append("No storm-related work recommended at this time. Proposal provided for record only.")
        }

        lines.append("All work performed in accordance with HAAG inspection findings and local building code. Manufacturer and workmanship warranties as listed below.")
        return lines.joined(separator: "\n\n")
    }
}
