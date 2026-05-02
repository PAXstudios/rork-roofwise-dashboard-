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
    let generatedAt: Date = Date()
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

        // Roof-covering specific overrides (e.g. concrete tile uses tile-damage % rules).
        let covering = detectedCovering(from: allFindings)
        var finalRecommendation = grade.recommendedAction
        var finalSummary = summary
        var damagedTilesPercent: Double? = nil

        if let covering, covering.contains("concrete tile") {
            let pct = estimatedDamagedTilesPercent(photos: photos)
            damagedTilesPercent = pct
            if pct >= 10 {
                finalRecommendation = "Replacement"
                finalSummary = String(
                    format: "Concrete tile roof: %.1f%% of visible tiles show damage (cracked, broken, slipped, or missing). Per concrete-tile criteria, damage at or above 10%% supports full Replacement rather than spot repair.",
                    pct
                )
            }
        }

        return ClaimPacket(grade: grade,
                           perils: perils,
                           affectedSquares: affectedSquares,
                           recommendation: finalRecommendation,
                           slopeFindings: entries,
                           summary: finalSummary,
                           roofCovering: covering,
                           damagedTilesPercent: damagedTilesPercent)
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
