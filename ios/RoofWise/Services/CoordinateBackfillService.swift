import Foundation
import CoreLocation

/// Resolves and backfills geocoded coordinates for leads (`Customer`) and
/// inspections (`InspectionJob`).
///
/// - `resolve(address:)` is the single-record entry point used on record
///   creation: cache-first, so a resolved address never geocodes twice across
///   launches.
/// - `backfill(customerStore:)` is the one-time migration: it loops every
///   existing record missing coordinates and resolves each sequentially
///   (CLGeocoder should not run concurrent requests), then stores the result.
@MainActor
final class CoordinateBackfillService {
    static let shared = CoordinateBackfillService()

    private let geocoder: GeocodingService = GeocodingServiceFactory.shared
    private var isBackfilling = false

    private init() {}

    /// Resolve a single address to a coordinate. Returns the cached value when
    /// present; otherwise geocodes once, caches the result, and returns it.
    /// Returns nil for empty/placeholder addresses or on geocode failure.
    @discardableResult
    func resolve(address: String) async -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("Add property") else { return nil }

        let key = GeocodeCache.normalize(trimmed)
        if let hit = GeocodeCache.shared.coordinate(forKey: key) { return hit }

        let coord = (try? await geocoder.geocode(trimmed)) ?? nil
        if let coord { GeocodeCache.shared.store(coord, forKey: key) }
        return coord
    }

    /// One-time migration: geocode every customer + inspection that has an
    /// address but no stored coordinate, then persist. Idempotent and
    /// cache-backed, so repeat runs are cheap and only touch new records.
    func backfill(customerStore: CustomerStore?) async {
        guard !isBackfilling else { return }
        isBackfilling = true
        defer { isBackfilling = false }

        if let store = customerStore {
            for customer in store.customers where customer.coordinate == nil && !customer.isUnassignedDraft {
                if let coord = await resolve(address: customer.address) {
                    store.setCoordinate(coord, for: customer.id)
                }
            }
        }

        for inspection in InspectionStore.shared.inspections where inspection.job.coordinate == nil {
            if let coord = await resolve(address: inspection.job.propertyAddress) {
                InspectionStore.shared.setCoordinate(coord, for: inspection.job.reportId)
            }
        }
    }
}
