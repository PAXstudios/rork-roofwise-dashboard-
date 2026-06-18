import SwiftUI
import MapKit
import CoreLocation

// MARK: - Storm display-helper layer
//
// Pure, deterministic helpers + small value types that turn the existing
// `StormPinEvent` (declared in Services/MapsService.swift) into a sales-grade
// map model: severity, recency, impact radius, intensity-scaled glyph size,
// plus the supporting models for footprint pins, route stops, service-area
// geometry, clustering and the heat-density grid.
//
// Storm-domain math is `nonisolated` so it can run off the main actor (used by
// the nonisolated clustering + route builder). The Color mappings that read
// `Theme` are `@MainActor`, isolated explicitly so this compiles cleanly under
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

// MARK: Severity

nonisolated enum StormSeverity: String, Sendable {
    case severe, moderate, minor

    var label: String {
        switch self {
        case .severe:   return "Severe"
        case .moderate: return "Moderate"
        case .minor:    return "Minor"
        }
    }

    /// Higher = worse. Used to pick the worst storm in a cluster.
    var rank: Int {
        switch self {
        case .severe:   return 2
        case .moderate: return 1
        case .minor:    return 0
        }
    }
}

extension StormSeverity {
    /// High-contrast, outdoor-sun-readable hues (no pastels).
    @MainActor var color: Color {
        switch self {
        case .severe:   return Theme.crimson
        case .moderate: return Theme.amber
        case .minor:    return Theme.inkFaint
        }
    }
}

// MARK: Filters

nonisolated enum StormKindFilter: String, CaseIterable, Identifiable, Sendable {
    case hail, wind, both
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hail: return "Hail"
        case .wind: return "Wind"
        case .both: return "Both"
        }
    }

    var icon: String {
        switch self {
        case .hail: return "cloud.hail.fill"
        case .wind: return "wind"
        case .both: return "cloud.bolt.rain.fill"
        }
    }
}

nonisolated enum StormDateRange: Hashable, Sendable {
    case last7, last30, last90, lastYear, all
    case custom(start: Date, end: Date)

    var label: String {
        switch self {
        case .last7:    return "Last 7 days"
        case .last30:   return "Last 30 days"
        case .last90:   return "Last 90 days"
        case .lastYear: return "Last 12 months"
        case .all:      return "All time"
        case .custom(let s, let e):
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "\(f.string(from: s)) – \(f.string(from: e))"
        }
    }

    /// Inclusive lower bound. `nil` for `.all` (no lower bound).
    var startDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .last7:    return cal.date(byAdding: .day, value: -7, to: now)
        case .last30:   return cal.date(byAdding: .day, value: -30, to: now)
        case .last90:   return cal.date(byAdding: .day, value: -90, to: now)
        case .lastYear: return cal.date(byAdding: .year, value: -1, to: now)
        case .all:      return nil
        case .custom(let start, _): return start
        }
    }

    /// Inclusive upper bound. `nil` means "up to now".
    var endDate: Date? {
        switch self {
        case .custom(_, let end): return end
        default: return nil
        }
    }

    /// Months of history to request from `StormEventsServicing` so the precise
    /// client-side date filter always has data to work with.
    var monthsBack: Int {
        switch self {
        case .last7:    return 1
        case .last30:   return 2
        case .last90:   return 4
        case .lastYear: return 13
        case .all:      return 120
        case .custom(let start, _):
            let months = Calendar.current.dateComponents([.month], from: start, to: Date()).month ?? 12
            return max(1, months + 1)
        }
    }

    /// True when `date` falls inside the range.
    func contains(_ date: Date) -> Bool {
        if let start = startDate, date < start { return false }
        if let end = endDate, date > end { return false }
        return true
    }
}

// MARK: StormPinEvent — pure display helpers (nonisolated)

extension StormPinEvent {
    /// Severity from magnitude. Hail by inches, wind by mph.
    nonisolated var severity: StormSeverity {
        if let h = hailSizeIn {
            if h >= 1.75 { return .severe }
            if h >= 1.0  { return .moderate }
            return .minor
        }
        if let w = windGustMph {
            if w >= 70 { return .severe }
            if w >= 58 { return .moderate }
            return .minor
        }
        return .minor
    }

    /// Probable damage footprint: 3 mi for hail, 5 mi for wind.
    nonisolated var impactRadiusMiles: Double { isHail ? 3.0 : 5.0 }

    nonisolated var impactRadiusMeters: Double { impactRadiusMiles * 1609.344 }

    /// Whole days since the storm (clamped ≥ 0).
    nonisolated var daysSince: Int {
        max(0, Int(Date().timeIntervalSince(date) / 86_400))
    }

    nonisolated var daysSinceBadge: String { "\(daysSince)d" }

    /// Pin diameter scales linearly with intensity, clamped to a glove-readable
    /// 30–56 pt so a 3" stone or a 120 mph gust reads big without overflowing.
    nonisolated var glyphDiameter: CGFloat {
        if let h = hailSizeIn {
            return min(56, max(30, 28 + CGFloat(h) * 9))
        }
        if let w = windGustMph {
            return min(56, max(30, 28 + CGFloat(max(0, w - 40)) * 0.28))
        }
        return 32
    }

    /// "H" for hail, "W" for wind — the white letter on the pin.
    nonisolated var typeLetter: String { isHail ? "H" : "W" }

    /// Compact magnitude string for sheets and route labels.
    nonisolated var magnitudeText: String {
        if let h = hailSizeIn { return String(format: "%.2f\" hail", h) }
        if let w = windGustMph { return "\(w) mph wind" }
        return "Storm"
    }
}

// MARK: StormPinEvent — Color mappings (@MainActor, read Theme)

extension StormPinEvent {
    @MainActor var severityColor: Color { severity.color }

    /// Recency: green ≤30d, amber 31–90d, gray >90d.
    @MainActor var recencyColor: Color {
        switch daysSince {
        case ...30:   return Theme.mint
        case 31...90: return Theme.amber
        default:      return Theme.inkFaint
        }
    }
}

// MARK: - Footprint pins (leads / scheduled inspections / signed jobs)

nonisolated struct FootprintPin: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case lead                 // open circle
        case scheduledInspection  // filled + calendar
        case signedJob            // filled + check
    }

    let id: UUID
    let kind: Kind
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), kind: Kind, title: String, subtitle: String,
         latitude: Double, longitude: Double) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    func distanceMiles(from coord: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1609.344
    }
}

extension FootprintPin.Kind {
    @MainActor var color: Color {
        switch self {
        case .lead:                return Theme.sky
        case .scheduledInspection: return Theme.amber
        case .signedJob:           return Theme.mint
        }
    }

    nonisolated var icon: String {
        switch self {
        case .lead:                return "person.fill"
        case .scheduledInspection: return "calendar"
        case .signedJob:           return "checkmark"
        }
    }

    /// Leads render as an open ring; booked work renders filled.
    nonisolated var isFilled: Bool { self != .lead }

    nonisolated var label: String {
        switch self {
        case .lead:                return "Lead"
        case .scheduledInspection: return "Inspection"
        case .signedJob:           return "Signed job"
        }
    }
}

// MARK: - Walking-route stop

nonisolated struct StormRouteStop: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let order: Int

    init(id: UUID = UUID(), title: String, subtitle: String,
         latitude: Double, longitude: Double, order: Int) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.order = order
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

// MARK: - Clustering (Step 8)
//
// SwiftUI's `Map` has no first-class annotation clustering, so we bucket pins
// into a grid whose cell size scales with the visible span. Zoomed in (span
// below `clusterAbove`) every storm renders individually; zoomed out, nearby
// storms collapse into one cluster pill coloured by the worst member.

nonisolated struct StormCluster: Identifiable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let members: [StormPinEvent]

    var count: Int { members.count }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var single: StormPinEvent? { count == 1 ? members.first : nil }

    /// Worst-severity member, used for the cluster colour.
    var worst: StormPinEvent? {
        members.max { $0.severity.rank < $1.severity.rank }
    }
}

nonisolated enum StormClustering {
    /// Cluster `storms` for the current latitude span. `clusterAbove` ≈ 0.14°
    /// which is roughly a 10-mile span.
    static func clusters(_ storms: [StormPinEvent],
                         spanLatDelta: Double,
                         clusterAbove: Double = 0.14) -> [StormCluster] {
        guard spanLatDelta > clusterAbove, storms.count > 1 else {
            return storms.map {
                StormCluster(id: $0.id.uuidString,
                             latitude: $0.latitude, longitude: $0.longitude,
                             members: [$0])
            }
        }
        let cell = max(0.01, spanLatDelta / 8.0)
        var buckets: [String: [StormPinEvent]] = [:]
        for s in storms {
            let gx = (s.latitude / cell).rounded(.down)
            let gy = (s.longitude / cell).rounded(.down)
            buckets["\(gx)_\(gy)", default: []].append(s)
        }
        return buckets.map { key, members in
            let lat = members.reduce(0) { $0 + $1.latitude } / Double(members.count)
            let lng = members.reduce(0) { $0 + $1.longitude } / Double(members.count)
            return StormCluster(id: key, latitude: lat, longitude: lng, members: members)
        }
    }
}

// MARK: - Service-area geometry (Step 3 stop-gap)
//
// `ServiceArea` only carries a geocoded centroid (no polygon), so we draw a
// square footprint sized by a radius around the centroid as a stand-in.

nonisolated enum ServiceAreaGeometry {
    static func boundingBox(center: CLLocationCoordinate2D,
                            radiusMiles: Double) -> [CLLocationCoordinate2D] {
        let dLat = radiusMiles / 69.0
        let dLng = radiusMiles / (69.0 * max(0.1, cos(center.latitude * .pi / 180)))
        return [
            .init(latitude: center.latitude - dLat, longitude: center.longitude - dLng),
            .init(latitude: center.latitude - dLat, longitude: center.longitude + dLng),
            .init(latitude: center.latitude + dLat, longitude: center.longitude + dLng),
            .init(latitude: center.latitude + dLat, longitude: center.longitude - dLng)
        ]
    }
}

// MARK: - Heat-density grid (Step 11)
//
// Hex math is overkill for a field tool, so we bucket storm events into ~2-mile
// square cells across the visible region and colour each by event count. OFF by
// default; toggled from the layer popover.

nonisolated struct HeatCell: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let count: Int
}

nonisolated enum StormHeatGrid {
    static func cells(storms: [StormPinEvent],
                      cellMiles: Double = 2.0) -> [HeatCell] {
        guard !storms.isEmpty else { return [] }
        // Use a representative latitude for the longitude scale.
        let refLat = storms.reduce(0) { $0 + $1.latitude } / Double(storms.count)
        let dLat = cellMiles / 69.0
        let dLng = cellMiles / (69.0 * max(0.1, cos(refLat * .pi / 180)))

        var buckets: [String: Int] = [:]
        var anchors: [String: (Double, Double)] = [:]
        for s in storms {
            let gx = (s.latitude / dLat).rounded(.down)
            let gy = (s.longitude / dLng).rounded(.down)
            let key = "\(gx)_\(gy)"
            buckets[key, default: 0] += 1
            if anchors[key] == nil {
                anchors[key] = (gx * dLat, gy * dLng)
            }
        }
        return buckets.compactMap { key, count in
            guard let (lat0, lng0) = anchors[key] else { return nil }
            let coords: [CLLocationCoordinate2D] = [
                .init(latitude: lat0,        longitude: lng0),
                .init(latitude: lat0,        longitude: lng0 + dLng),
                .init(latitude: lat0 + dLat, longitude: lng0 + dLng),
                .init(latitude: lat0 + dLat, longitude: lng0)
            ]
            return HeatCell(id: key, coordinates: coords, count: count)
        }
    }
}

extension HeatCell {
    /// Ember→crimson ramp by relative density.
    @MainActor func fillColor(maxCount: Int) -> Color {
        let t = maxCount <= 1 ? 1.0 : Double(count - 1) / Double(maxCount - 1)
        let alpha = 0.18 + 0.42 * min(1.0, max(0.0, t))
        return (t > 0.6 ? Theme.crimson : Theme.ember).opacity(alpha)
    }
}
