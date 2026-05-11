import Foundation
import Observation
import CoreLocation
import SwiftUI

@Observable
final class KnockStore {
    var houses: [KnockedHouse]
    /// Last known coordinate from CLLocationManager (used to stamp new pins).
    var lastLocation: CLLocationCoordinate2D?

    init() {
        // Clean empty state — no seeded sample knocks. Real pins arrive from
        // the live map (`add(coord:)`) or door-knocking flow.
        self.houses = []
    }

    /// Place a house pin at a real-world coordinate (used by the live map).
    @discardableResult
    func add(coord: CLLocationCoordinate2D, outcome: KnockOutcome = .notKnocked) -> KnockedHouse {
        var h = KnockedHouse(x: 0, y: 0, outcome: outcome)
        h.latitude = coord.latitude
        h.longitude = coord.longitude
        houses.append(h)
        return h
    }

    func add(at point: CGPoint, outcome: KnockOutcome = .notKnocked) -> KnockedHouse {
        var h = KnockedHouse(x: point.x, y: point.y, outcome: outcome)
        if let loc = lastLocation {
            // Tiny perturbation per pin to avoid all stamps being identical
            h.latitude = loc.latitude + Double.random(in: -0.0006...0.0006)
            h.longitude = loc.longitude + Double.random(in: -0.0006...0.0006)
        }
        // No DFW fallback — pin is left without coords if location is unknown.
        houses.append(h)
        return h
    }

    func update(_ house: KnockedHouse) {
        if let i = houses.firstIndex(where: { $0.id == house.id }) {
            houses[i] = house
        }
    }

    func remove(_ id: UUID) {
        houses.removeAll { $0.id == id }
    }

    func count(of outcome: KnockOutcome) -> Int {
        houses.filter { $0.outcome == outcome }.count
    }
}
