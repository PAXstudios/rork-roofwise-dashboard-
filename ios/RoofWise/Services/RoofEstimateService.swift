import Foundation
import CoreLocation

/// Computes an accurate roof measurement (Google Solar when a live key is
/// configured, otherwise a deterministic estimate) plus a repair-cost estimate
/// for a customer, entirely in the background, and writes the result back into
/// `CustomerStore`. Kicked off when a job is created from an address so the
/// numbers are ready by the time the inspector opens the profile.
@MainActor
enum RoofEstimateService {

    /// Geocode → Google Solar measurement → cost estimate, then persist on the
    /// customer. Safe to call fire-and-forget; updates the store as it lands.
    static func computeInBackground(customerID: UUID,
                                    address: String,
                                    material: RoofPrimaryMaterial,
                                    store: CustomerStore) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return }
        store.setEstimating(customerID, true)
        Task { @MainActor in
            // 1. Resolve a coordinate — prefer the real CLGeocoder result.
            let coord: CLLocationCoordinate2D
            if let geo = try? await GeocodingServiceFactory.shared.geocode(trimmed) {
                coord = geo
            } else {
                coord = GeocodingServiceFactory.eagerCoord(forAddress: trimmed)
            }
            // 2. Measure the roof (Google Solar when live).
            guard let measurement = try? await SolarServiceFactory.shared.measurements(at: coord) else {
                store.setEstimating(customerID, false)
                return
            }
            // 3. Price the repair from the measurement + material.
            let estimate = CostEstimator.estimate(measurement: measurement,
                                                  material: material,
                                                  address: trimmed)
            store.applyRoofEstimate(customerID: customerID,
                                    measurement: measurement,
                                    estimate: estimate)
        }
    }

    /// Compact money label for the lead card / header capsule, e.g. "$18.5k–$22.4k".
    static func compactRange(low: Double, high: Double) -> String {
        "\(compact(low))–\(compact(high))"
    }

    private static func compact(_ v: Double) -> String {
        if v >= 1000 {
            let k = v / 1000.0
            // 18.5k below 100k, whole-number k above.
            return k >= 100 ? String(format: "$%.0fk", k) : String(format: "$%.1fk", k)
        }
        return "$\(Int(v.rounded()))"
    }
}
