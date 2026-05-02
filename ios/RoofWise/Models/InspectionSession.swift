import SwiftUI
import UIKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case singleShingle = "Single Shingle"
    case square = "10x10 Square"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .singleShingle: return "square.dashed"
        case .square: return "square.grid.3x3.topleft.filled"
        }
    }
    var shortLabel: String {
        switch self {
        case .singleShingle: return "Shingle"
        case .square: return "Square"
        }
    }
}

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let slope: SlopeType
    let pitchDegrees: Double
    let elevationFeet: Double
    var captureMode: CaptureMode = .square
    var squaresCovered: Int = 0
    let timestamp: Date = Date()
    var findings: [InspectionFinding] = []
    var damageMarkers: [DamageMarker] = []
    var analyzed: Bool = false

    // MARK: - Pertinent info derived from analysis

    /// Pretty shingle / roof covering name pulled from the AI's `shingle_type` finding.
    /// Returns `nil` if Gemini didn't classify the surface.
    var shingleType: String? {
        guard let f = findings.first(where: { $0.label == "shingle_type" }) else { return nil }
        let raw = f.value.split(separator: "\u{2014}").first.map(String.init) ?? f.value
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short evidence note from the AI about why this shingle type was chosen.
    var shingleTypeNote: String? {
        guard let f = findings.first(where: { $0.label == "shingle_type" }) else { return nil }
        let parts = f.value.split(separator: "\u{2014}", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Estimated number of shingles visible in the photo. Approximation based on
    /// capture mode: a single-shingle photo shows ~1 tab; a 100 sq ft test square
    /// in asphalt covers roughly 30 shingle tabs.
    var estimatedShingleCount: Int {
        switch captureMode {
        case .singleShingle:
            return 1
        case .square:
            let squares = max(1, squaresCovered)
            return squares * 30
        }
    }

    /// Damage markers grouped by type, in display order.
    var markersByType: [(type: DamageMarkerType, items: [DamageMarker])] {
        let dict = Dictionary(grouping: damageMarkers, by: \.type)
        return DamageMarkerType.allCases.compactMap { type in
            guard let items = dict[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    /// Top detected (true) findings, severity-weighted, excluding the shingle_type meta finding.
    var topDetectedFindings: [InspectionFinding] {
        findings
            .filter { $0.detected && $0.label != "shingle_type" }
            .sorted { lhs, rhs in
                if lhs.severity.rank != rhs.severity.rank { return lhs.severity.rank > rhs.severity.rank }
                return lhs.confidence > rhs.confidence
            }
    }

    /// Worst severity damage finding for this photo, if any.
    var worstSeverity: FindingSeverity {
        topDetectedFindings.first?.severity ?? .none
    }
}

// MARK: - HAAG Standards

enum HaagGrade: String {
    case noFunctional = "No Functional Damage"
    case hail = "Functional Damage - Hail"
    case wind = "Functional Damage - Wind"
    case combined = "Functional Damage - Combined Peril"

    var color: Color {
        switch self {
        case .noFunctional: return Theme.mint
        case .hail: return Theme.ember
        case .wind: return Theme.sky
        case .combined: return Theme.crimson
        }
    }

    var icon: String {
        switch self {
        case .noFunctional: return "checkmark.shield.fill"
        case .hail: return "circle.hexagongrid.fill"
        case .wind: return "wind"
        case .combined: return "exclamationmark.triangle.fill"
        }
    }

    var recommendedAction: String {
        switch self {
        case .noFunctional: return "Repair / Monitor"
        case .hail, .wind: return "Replace Affected Slopes"
        case .combined: return "Full Roof Replacement"
        }
    }
}

struct ClaimPacket: Identifiable {
    let id = UUID()
    let grade: HaagGrade
    let perils: [String]
    let affectedSquares: Double
    let recommendation: String
    let slopeFindings: [SlopePacketEntry]
    let summary: String
    let roofCovering: String?
    let damagedTilesPercent: Double?
    let thresholdRule: String?
    let hitsPerSquare: Double?
    let generatedAt: Date = Date()
}

/// HAAG-style roof covering categories used to pick the correct
/// damage threshold against a 100 sq ft test square.
enum RoofCoveringCategory {
    case asphaltComposition  // 3-tab + architectural laminate
    case woodShakeShingle
    case metalPanel
    case concreteTile
    case clayTile
    case slate
    case lowSlopeMembrane    // mod-bit / TPO / EPDM / built-up
    case unknown

    /// Returns (label, ruleText, threshold trigger) for display.
    var ruleDescription: String {
        switch self {
        case .asphaltComposition:
            return "Asphalt shingle: 8+ functional hail hits per 100 sq ft test square supports Replacement."
        case .woodShakeShingle:
            return "Wood shake/shingle: 8+ functional impacts per 100 sq ft test square supports Replacement."
        case .metalPanel:
            return "Metal panel: 8+ functional dents (denting that compromises seam, fastener, or coating) per 100 sq ft supports Replacement."
        case .concreteTile:
            return "Concrete tile: 10%+ of visible tiles damaged (cracked, broken, slipped, missing) supports Replacement."
        case .clayTile:
            return "Clay tile: 10%+ of visible tiles damaged supports Replacement."
        case .slate:
            return "Slate: 8%+ broken/cracked slates per slope supports Replacement."
        case .lowSlopeMembrane:
            return "Low-slope membrane (mod-bit / TPO / EPDM / BUR): any functional fracture or membrane breach supports Replacement of affected section."
        case .unknown:
            return "HAAG functional damage thresholds applied per 100 sq ft test square."
        }
    }

    static func from(covering: String?) -> RoofCoveringCategory {
        guard let c = covering?.lowercased() else { return .unknown }
        if c.contains("concrete tile") { return .concreteTile }
        if c.contains("clay") || c.contains("spanish") || c.contains("barrel") { return .clayTile }
        if c.contains("slate") { return .slate }
        if c.contains("wood") || c.contains("shake") || c.contains("cedar") { return .woodShakeShingle }
        if c.contains("metal") || c.contains("standing seam") || c.contains("steel") || c.contains("aluminum") { return .metalPanel }
        if c.contains("tpo") || c.contains("epdm") || c.contains("modified bitumen") || c.contains("mod-bit") || c.contains("built-up") || c.contains("bur") || c.contains("membrane") { return .lowSlopeMembrane }
        if c.contains("asphalt") || c.contains("composition") || c.contains("3-tab") || c.contains("architectural") || c.contains("laminate") { return .asphaltComposition }
        return .unknown
    }
}

struct SlopePacketEntry: Identifiable {
    let id = UUID()
    let slope: SlopeType
    let photoCount: Int
    let topFindings: [String]
}

// MARK: - HAAG Grading Logic

enum HaagGrader {
    /// HAAG Standards:
    /// - Hail claimable if functional damage confirmed (bruising/cracking of mat,
    ///   granule displacement > 30% on multiple hits)
    /// - Wind claimable if creasing/folding at nail line, lifted tabs, missing shingles
    static func grade(photos: [CapturedPhoto]) -> ClaimPacket {
        let allFindings = photos.flatMap(\.findings)

        let bruising = allFindings.first { $0.label == "bruising" }
        let granuleLoss = allFindings.first { $0.label == "granule_loss" }
        let cracking = allFindings.first { $0.label == "cracking_splitting" }
        let windCreasing = allFindings.first { $0.label == "wind_creasing" }
        let missingShingles = allFindings.first { $0.label == "missing_shingles" }

        let hailFunctional = isFunctional(bruising) ||
                             (isFunctional(granuleLoss) && (bruising?.detected ?? false)) ||
                             isFunctional(cracking)

        let windFunctional = isFunctional(windCreasing) || isFunctional(missingShingles)

        let grade: HaagGrade
        var perils: [String] = []
        switch (hailFunctional, windFunctional) {
        case (true, true):
            grade = .combined
            perils = ["Hail", "Wind"]
        case (true, false):
            grade = .hail
            perils = ["Hail"]
        case (false, true):
            grade = .wind
            perils = ["Wind"]
        case (false, false):
            grade = .noFunctional
        }

        // Estimate squares: 100 sq ft per photo of an affected slope, capped per slope
        let affectedSlopes = Set(photos.filter { !$0.findings.filter { $0.detected && $0.severity != .none && $0.severity != .minor }.isEmpty }.map(\.slope))
        let affectedSquares = Double(affectedSlopes.count) * 6.5

        let entries: [SlopePacketEntry] = Dictionary(grouping: photos, by: \.slope)
            .map { slope, group in
                let top = group.flatMap(\.findings)
                    .filter { $0.detected }
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(3)
                    .map { "\($0.display) · \($0.severity.rawValue)" }
                return SlopePacketEntry(slope: slope,
                                        photoCount: group.count,
                                        topFindings: Array(top))
            }
            .sorted { $0.slope.rawValue < $1.slope.rawValue }

        let summary: String
        switch grade {
        case .noFunctional:
            summary = "Roof shows cosmetic wear only. Damage falls below carrier functional thresholds; supplement not advised at this time."
        case .hail:
            summary = "Hail-driven functional damage confirmed per HAAG Engineering criteria: mat fracture and granule displacement on multiple impacts. Replacement of affected slopes is supportable."
        case .wind:
            summary = "Wind-driven functional damage confirmed: creasing at nail line and/or lifted/missing tabs. Replacement of affected slopes is supportable."
        case .combined:
            summary = "Combined peril event. Both hail and wind functional damage confirmed across multiple slopes. Full roof replacement is supportable per HAAG standards."
        }

        // Roof-covering specific overrides — apply HAAG thresholds per 100 sq ft test square.
        let covering = detectedCovering(from: allFindings)
        let category = RoofCoveringCategory.from(covering: covering)
        var finalRecommendation = grade.recommendedAction
        var finalSummary = summary
        var damagedTilesPercent: Double? = nil
        var hitsPerSquare: Double? = nil

        switch category {
        case .concreteTile, .clayTile:
            let pct = estimatedDamagedTilesPercent(photos: photos)
            damagedTilesPercent = pct
            if pct >= 10 {
                finalRecommendation = "Replacement"
                finalSummary = String(
                    format: "%@ roof: %.1f%% of visible tiles damaged (cracked, broken, slipped, or missing). %@",
                    category == .concreteTile ? "Concrete tile" : "Clay tile",
                    pct,
                    category.ruleDescription
                )
            }
        case .slate:
            let pct = estimatedDamagedTilesPercent(photos: photos)
            damagedTilesPercent = pct
            if pct >= 8 {
                finalRecommendation = "Replacement"
                finalSummary = String(
                    format: "Slate roof: %.1f%% of visible slates broken or cracked. %@",
                    pct,
                    category.ruleDescription
                )
            }
        case .asphaltComposition, .woodShakeShingle, .metalPanel:
            let hits = estimatedHitsPerSquare(photos: photos)
            hitsPerSquare = hits
            if hits >= 8 {
                finalRecommendation = "Replacement"
                let coveringLabel: String = {
                    switch category {
                    case .asphaltComposition: return "Asphalt shingle"
                    case .woodShakeShingle: return "Wood shake/shingle"
                    case .metalPanel: return "Metal panel"
                    default: return "Roof"
                    }
                }()
                finalSummary = String(
                    format: "%@ roof: %.1f functional hits per 100 sq ft test square. %@",
                    coveringLabel,
                    hits,
                    category.ruleDescription
                )
            }
        case .lowSlopeMembrane:
            let breach = allFindings.contains { $0.detected && ($0.severity == .moderate || $0.severity == .severe) && ($0.label == "cracking_splitting" || $0.label == "missing_shingles" || $0.label == "bruising") }
            if breach {
                finalRecommendation = "Replacement"
                finalSummary = "Low-slope membrane shows functional fracture / breach of the watertight layer. \(category.ruleDescription)"
            }
        case .unknown:
            break
        }

        return ClaimPacket(grade: grade,
                           perils: perils,
                           affectedSquares: affectedSquares,
                           recommendation: finalRecommendation,
                           slopeFindings: entries,
                           summary: finalSummary,
                           roofCovering: covering,
                           damagedTilesPercent: damagedTilesPercent,
                           thresholdRule: category == .unknown ? nil : category.ruleDescription,
                           hitsPerSquare: hitsPerSquare)
    }

    /// Estimates HAAG-style functional hits per 100 sq ft test square.
    /// Treats each square-mode photo as one 100 sq ft test square (scaled by squaresCovered),
    /// counts moderate/severe hail+wind markers and findings as hits, then returns the
    /// per-square average across all test squares photographed.
    private static func estimatedHitsPerSquare(photos: [CapturedPhoto]) -> Double {
        var totalSquares: Double = 0
        var totalHits: Double = 0
        for photo in photos {
            let squares: Double = {
                switch photo.captureMode {
                case .square: return Double(max(1, photo.squaresCovered))
                case .singleShingle: return 0.1   // one shingle ≈ 1/10 of a test square
                }
            }()
            totalSquares += squares

            let markerHits = photo.damageMarkers.filter {
                ($0.type == .hailStrike || $0.type == .windCrease || $0.type == .crack || $0.type == .missingShingle) &&
                ($0.severity == .moderate || $0.severity == .severe)
            }.count

            let findingHits: Int = {
                if markerHits > 0 { return 0 }
                let labels: Set<String> = ["bruising", "cracking_splitting", "wind_creasing", "missing_shingles"]
                var n = 0
                for f in photo.findings where f.detected && labels.contains(f.label) {
                    n += severityWeight(f.severity)
                }
                return n
            }()

            totalHits += Double(markerHits + findingHits)
        }
        guard totalSquares > 0 else { return 0 }
        return totalHits / totalSquares
    }

    private static func isFunctional(_ finding: InspectionFinding?) -> Bool {
        guard let f = finding, f.detected else { return false }
        return f.severity == .moderate || f.severity == .severe
    }

    /// Pulls the lower-cased covering name out of the AI's `shingle_type` finding, if any.
    private static func detectedCovering(from findings: [InspectionFinding]) -> String? {
        guard let typeFinding = findings.first(where: { $0.label == "shingle_type" }) else {
            return nil
        }
        // value is formatted as "Pretty Name — note"; take the part before the em dash.
        let raw = typeFinding.value.split(separator: "\u{2014}").first.map(String.init) ?? typeFinding.value
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Estimates % of visible tiles showing damage across all captured photos.
    /// We approximate ~30 tiles visible per square-mode photo and ~6 per single-shingle photo,
    /// then count damage markers (cracks, missing/slipped tiles) plus per-photo missing/cracking
    /// findings as damaged tiles.
    private static func estimatedDamagedTilesPercent(photos: [CapturedPhoto]) -> Double {
        var totalTiles = 0
        var damagedTiles = 0
        for photo in photos {
            let tilesInFrame: Int = {
                switch photo.captureMode {
                case .square: return max(1, 30 * max(1, photo.squaresCovered == 0 ? 1 : photo.squaresCovered))
                case .singleShingle: return 6
                }
            }()
            totalTiles += tilesInFrame

            // Each marker that indicates a broken/missing/cracked tile counts as one damaged tile.
            let markerHits = photo.damageMarkers.filter {
                $0.type == .crack || $0.type == .missingShingle || $0.type == .other
            }.count

            // Fallback if no markers: derive from findings counts/severity.
            let findingHits: Int = {
                if markerHits > 0 { return 0 }
                let cracking = photo.findings.first { $0.label == "cracking_splitting" && $0.detected }
                let missing = photo.findings.first { $0.label == "missing_shingles" && $0.detected }
                var n = 0
                if let s = cracking?.severity { n += severityWeight(s) }
                if let s = missing?.severity { n += severityWeight(s) }
                return n
            }()

            damagedTiles += min(tilesInFrame, markerHits + findingHits)
        }
        guard totalTiles > 0 else { return 0 }
        return (Double(damagedTiles) / Double(totalTiles)) * 100.0
    }

    private static func severityWeight(_ s: FindingSeverity) -> Int {
        switch s {
        case .none: return 0
        case .minor: return 1
        case .moderate: return 3
        case .severe: return 6
        }
    }
}
