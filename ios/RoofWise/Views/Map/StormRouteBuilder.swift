import Foundation
import CoreLocation

// MARK: - Door-knock route builder (Step 7)
//
// Builds an ordered walking route for "Door Knock This Storm". There is no
// third-party home-density source wired in, so the route is composed strictly
// from REAL pins the user already owns — open leads inside the storm's impact
// footprint — never fabricated addresses. Candidates are:
//
//   • inside the storm impact radius (3 mi hail / 5 mi wind)
//   • inside a saved service area, when the user has any
//   • not already knocked (de-duped against logged knocks)
//
// They're ordered nearest-first from the user's live location (falling back to
// the storm centroid), and the stop cap scales with storm severity so a severe
// storm justifies a longer canvassing loop.

nonisolated enum StormRouteBuilder {
    /// Maximum stops by severity — severe storms warrant a longer route.
    static func cap(for severity: StormSeverity) -> Int {
        switch severity {
        case .severe:   return 25
        case .moderate: return 18
        case .minor:    return 12
        }
    }

    static func build(
        storm: StormPinEvent,
        userLocation: CLLocationCoordinate2D?,
        leads: [FootprintPin],
        visited: [CLLocationCoordinate2D],
        serviceAreas: [ServiceArea],
        maxStops: Int? = nil
    ) -> [StormRouteStop] {
        let stormCenter = storm.coordinate
        let origin = userLocation ?? stormCenter
        let radius = storm.impactRadiusMiles

        // Service-area gate: keep leads within 5 mi of any geocoded service-area
        // centroid. No areas configured → no geographic gate.
        let areaCentroids: [CLLocationCoordinate2D] = serviceAreas.compactMap { area in
            guard let lat = area.centerLat, let lng = area.centerLng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        func insideServiceArea(_ coord: CLLocationCoordinate2D) -> Bool {
            guard !areaCentroids.isEmpty else { return true }
            return areaCentroids.contains { centroid in
                CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: CLLocation(latitude: centroid.latitude, longitude: centroid.longitude))
                    / 1609.344 <= 5.0
            }
        }

        func alreadyVisited(_ coord: CLLocationCoordinate2D) -> Bool {
            visited.contains { v in
                CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    .distance(from: CLLocation(latitude: v.latitude, longitude: v.longitude)) <= 35 // ~1 house
            }
        }

        let candidates = leads
            .filter { $0.kind == .lead }
            .filter { $0.distanceMiles(from: stormCenter) <= radius }
            .filter { insideServiceArea($0.coordinate) }
            .filter { !alreadyVisited($0.coordinate) }

        let ordered = candidates.sorted {
            $0.distanceMiles(from: origin) < $1.distanceMiles(from: origin)
        }

        let limit = maxStops ?? cap(for: storm.severity)
        return ordered.prefix(limit).enumerated().map { idx, pin in
            StormRouteStop(
                title: pin.title,
                subtitle: pin.subtitle,
                latitude: pin.latitude,
                longitude: pin.longitude,
                order: idx + 1
            )
        }
    }
}
