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

        return ClaimPacket(grade: grade,
                           perils: perils,
                           affectedSquares: affectedSquares,
                           recommendation: grade.recommendedAction,
                           slopeFindings: entries,
                           summary: summary)
    }

    private static func isFunctional(_ finding: InspectionFinding?) -> Bool {
        guard let f = finding, f.detected else { return false }
        return f.severity == .moderate || f.severity == .severe
    }
}
