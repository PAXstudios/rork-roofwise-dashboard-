import Foundation
import CoreLocation

/// Disk-backed cache mapping a normalized address → coordinate.
///
/// Geocoding (Apple CLGeocoder) is rate-limited and shouldn't be repeated for
/// the same address across launches, so resolved coordinates persist here in
/// `UserDefaults`. This is the durable store behind `Customer`/`InspectionJob`
/// coordinates: the backfill reads it first and only hits the network on a miss.
@MainActor
final class GeocodeCache {
    static let shared = GeocodeCache()

    private let defaultsKey = "rw.geocodeCache.v1"
    private var map: [String: [Double]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            map = decoded
        } else {
            map = [:]
        }
    }

    /// Normalized lookup key — lowercased, whitespace-collapsed address.
    static func normalize(_ address: String) -> String {
        address
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func coordinate(forKey key: String) -> CLLocationCoordinate2D? {
        guard let pair = map[key], pair.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }

    func coordinate(forAddress address: String) -> CLLocationCoordinate2D? {
        coordinate(forKey: Self.normalize(address))
    }

    func store(_ coord: CLLocationCoordinate2D, forKey key: String) {
        guard !key.isEmpty else { return }
        map[key] = [coord.latitude, coord.longitude]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
