import SwiftUI
import simd

/// One AR damage marker placed in 3D space.
struct ARDamageMarker: Identifiable, Hashable {
    enum Source: String { case userTap, gemini }

    let id: UUID
    let type: DamageMarkerType
    let position: SIMD3<Float>     // world-space anchor position (meters)
    let note: String
    let source: Source
    let timestamp: Date

    init(id: UUID = UUID(),
         type: DamageMarkerType,
         position: SIMD3<Float>,
         note: String,
         source: Source,
         timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.position = position
        self.note = note
        self.source = source
        self.timestamp = timestamp
    }
}

/// Snapshot of an AR inspection saved back into the standard `CapturedPhoto`
/// pipeline so the rest of the app (HAAG grader, claim packet, PDF report)
/// keeps working unchanged.
struct ARInspectionSnapshot {
    let snapshotImage: UIImage
    let markers: [ARDamageMarker]
    let chalkStrokeCount: Int
    let pitchDegrees: Double
    let pitchRatio: String      // e.g. "6:12"
    let hitsInSquare: Int
    let squarePlaced: Bool
    let slope: SlopeType
    /// Real roof surface area derived from the LiDAR mesh, when available.
    /// `nil` on non-LiDAR devices — callers should fall back to their
    /// previous square-footage estimate in that case.
    var lidarRoofAreaSquareFeet: Double? = nil
    /// Pitch read from the LiDAR mesh's surface normal. Replaces the
    /// gyroscope estimate when available.
    var lidarPitchDegrees: Double? = nil
    /// USDZ file baked at save-time so the results screen can hand it to
    /// QuickLook without restarting the AR session.
    var usdzReportURL: URL? = nil
}

/// Tool the user has currently selected in the AR HUD.
enum ARTool: String, CaseIterable, Identifiable {
    case marker
    case chalk
    case placeSquare

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .marker:      return "mappin.and.ellipse"
        case .chalk:       return "scribble.variable"
        case .placeSquare: return "square.dashed.inset.filled"
        }
    }

    var label: String {
        switch self {
        case .marker:      return "Pin"
        case .chalk:       return "Chalk"
        case .placeSquare: return "10×10"
        }
    }
}

/// Roof pitch helpers — convert plane-tilt angle to standard roofing rise:run.
enum RoofPitch {
    /// `angle` is the tilt of the surface from horizontal, in radians.
    static func ratio(forAngle angle: Double) -> String {
        let rise = max(0, Int((tan(angle) * 12).rounded()))
        return "\(rise):12"
    }

    static func degrees(forAngle angle: Double) -> Double { angle * 180.0 / .pi }
}
