import CoreGraphics

/// Multi-photo per-slope consensus for AI damage markers.
///
/// Inspectors shoot a slope from several overlapping angles. A real hail strike
/// shows up in more than one frame; a single-frame, low-confidence blob is much
/// more likely to be an artifact. This merges a slope's per-photo marker sets:
/// markers that corroborate across ≥2 photos get a confidence boost, lone
/// low-confidence markers are dropped, and overlapping detections are de-duped so
/// the same strike isn't counted twice toward the HAAG hits-per-square total.
///
/// Pure + deterministic. Gated by `APIKeys.useMultiPhotoConsensus` at the call
/// site. NOTE: not yet wired into `QuickInspectionView.runScan` (the sacred
/// camera flow) — enable there in a Mac-verified change; see SPEC_AUDIT.md.
enum MarkerConsensus {

    /// Distance (normalized image space) under which two same-type markers are
    /// considered the same physical feature seen from different frames.
    static let mergeRadius: CGFloat = 0.06
    /// Lone single-frame markers below this confidence are dropped as noise.
    static let lonelyConfidenceFloor = 45
    /// Confidence boost applied to markers corroborated across ≥2 frames.
    static let corroborationBoost = 15

    /// Merge a slope's per-photo marker groups into a single de-duped, consensus
    /// set. `groups` = one array of markers per photo of the slope.
    static func merge(_ groups: [[DamageMarker]]) -> [DamageMarker] {
        let flattened: [(marker: DamageMarker, group: Int)] = groups.enumerated()
            .flatMap { gi, markers in markers.map { ($0, gi) } }
        guard !flattened.isEmpty else { return [] }
        guard groups.count > 1 else { return groups.first ?? [] }

        var used = [Bool](repeating: false, count: flattened.count)
        var output: [DamageMarker] = []

        for i in flattened.indices where !used[i] {
            used[i] = true
            var cluster = [flattened[i]]

            for j in flattened.indices where !used[j] {
                guard flattened[j].marker.type == flattened[i].marker.type else { continue }
                if anyWithin(mergeRadius, of: flattened[j].marker, in: cluster.map(\.marker)) {
                    used[j] = true
                    cluster.append(flattened[j])
                }
            }

            let distinctFrames = Set(cluster.map(\.group)).count
            // Representative = highest-confidence detection in the cluster.
            guard let best = cluster.map(\.marker).max(by: { $0.confidence < $1.confidence }) else { continue }

            if distinctFrames >= 2 {
                let boosted = min(100, best.confidence + corroborationBoost)
                output.append(rebuild(best, confidence: boosted))
            } else if best.confidence >= lonelyConfidenceFloor {
                output.append(best)
            }
            // else: single-frame low-confidence marker → dropped as noise.
        }
        return output
    }

    // MARK: - Helpers

    private static func anyWithin(_ r: CGFloat, of m: DamageMarker, in others: [DamageMarker]) -> Bool {
        for o in others {
            let dx = m.x - o.x, dy = m.y - o.y
            if (dx * dx + dy * dy).squareRoot() <= r { return true }
        }
        return false
    }

    private static func rebuild(_ m: DamageMarker, confidence: Int) -> DamageMarker {
        DamageMarker(x: m.x, y: m.y, radius: m.radius,
                     type: m.type, severity: m.severity,
                     note: m.note, confidence: confidence)
    }
}
