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
        self.houses = [
            KnockedHouse(x: 0.22, y: 0.34, outcome: .interested,
                         notes: "Owner has hail damage, wants Tuesday inspection."),
            KnockedHouse(x: 0.41, y: 0.28, outcome: .noAnswer,
                         notes: "Drove by 2x, no one home. Door hanger left."),
            KnockedHouse(x: 0.55, y: 0.46, outcome: .notInterested,
                         notes: "Just had roof done in 2023."),
            KnockedHouse(x: 0.68, y: 0.36, outcome: .scheduled,
                         notes: "Inspection booked Thu 9am. State Farm policy."),
            KnockedHouse(x: 0.30, y: 0.58, outcome: .notKnocked,
                         notes: ""),
            KnockedHouse(x: 0.74, y: 0.62, outcome: .interested,
                         notes: "Ask about granddaughter's policy too.")
        ]
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
