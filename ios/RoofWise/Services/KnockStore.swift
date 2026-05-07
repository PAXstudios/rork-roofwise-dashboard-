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
        // Seed with a few canvassed houses so the screen feels alive.
        // Coordinates are real DFW lat/lngs so they render on the live map.
        self.houses = [
            Self.seed(lat: 33.0631, lng: -96.7517, .interested,
                      notes: "Owner has hail damage, wants Tuesday inspection."),
            Self.seed(lat: 33.0712, lng: -96.7388, .noAnswer,
                      notes: "Drove by 2x, no one home. Door hanger left."),
            Self.seed(lat: 33.0584, lng: -96.7402, .notInterested,
                      notes: "Just had roof done in 2023."),
            Self.seed(lat: 33.0668, lng: -96.7321, .scheduled,
                      notes: "Inspection booked Thu 9am. State Farm policy."),
            Self.seed(lat: 33.0511, lng: -96.7458, .notKnocked,
                      notes: ""),
            Self.seed(lat: 33.0742, lng: -96.7234, .interested,
                      notes: "Ask about granddaughter's policy too.")
        ]
    }

    private static func seed(lat: Double, lng: Double, _ outcome: KnockOutcome, notes: String) -> KnockedHouse {
        var h = KnockedHouse(x: 0, y: 0, outcome: outcome, notes: notes)
        h.latitude = lat
        h.longitude = lng
        return h
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
        } else {
            // Fallback Plano TX area so the demo data stays plausible
            h.latitude = 33.0198 + Double.random(in: -0.005...0.005)
            h.longitude = -96.6989 + Double.random(in: -0.005...0.005)
        }
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
