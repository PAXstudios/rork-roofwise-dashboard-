import Foundation
import simd

/// Inspector-placed damage marker. Created by tapping anywhere on the live
/// camera preview. Positions are stored as normalized (0-1) coordinates in the
/// preview view's coordinate space so the dot stays anchored as the screen
/// resizes. On LiDAR devices the optional `worldPosition` can be set when the
/// tap is raycast against the LiDAR mesh and the marker is also anchored in
/// 3D space via an ARAnchor.
struct ManualDamageMarker: Identifiable, Equatable {
    let id: UUID
    var x: Float           // normalized 0-1 (left → right)
    var y: Float           // normalized 0-1 (top → bottom)
    var type: DamageMarkerType
    var severity: String   // "low" | "medium" | "high"
    var note: String?
    var timestamp: Date
    /// Optional 3D world position (LiDAR raycast result). nil on non-LiDAR
    /// devices or when no plane/mesh hit was available.
    var worldPosition: SIMD3<Float>?

    init(id: UUID = UUID(),
         x: Float,
         y: Float,
         type: DamageMarkerType,
         severity: String,
         note: String? = nil,
         timestamp: Date = Date(),
         worldPosition: SIMD3<Float>? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.type = type
        self.severity = severity
        self.note = note
        self.timestamp = timestamp
        self.worldPosition = worldPosition
    }

    var severityDisplay: String {
        switch severity.lowercased() {
        case "low": return "Low"
        case "high": return "High"
        default: return "Medium"
        }
    }
}

extension ManualDamageMarker {
    /// Inspector-selectable damage types for manual marking.
    static let allowedTypes: [DamageMarkerType] = [
        .hailStrike, .shingleBruise, .windCrease, .crack,
        .missingShingle, .liftedShingle, .tornShingle, .exposedMat
    ]
}
