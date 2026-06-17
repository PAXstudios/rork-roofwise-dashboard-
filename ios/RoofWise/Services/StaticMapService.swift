import Foundation
import CoreLocation

/// Builds Google Static Maps URLs for high-zoom satellite (aerial) imagery of a
/// property roof. Uses the same unrestricted Google Cloud key as Maps / Solar /
/// Geocoding. Pure URL construction — no network call here.
nonisolated enum StaticMapService {

    /// A top-down satellite tile centered on `coord`, sized for a hero card.
    /// `zoom` 20 frames a single residential roof; `scale: 2` returns retina px.
    static func satelliteURL(for coord: CLLocationCoordinate2D,
                             zoom: Int = 20,
                             width: Int = 640,
                             height: Int = 420,
                             scale: Int = 2) -> URL? {
        guard !APIKeys.googleMapsApiKey.isEmpty else { return nil }
        var comps = URLComponents(string: "https://maps.googleapis.com/maps/api/staticmap")!
        comps.queryItems = [
            .init(name: "center", value: "\(coord.latitude),\(coord.longitude)"),
            .init(name: "zoom",    value: String(zoom)),
            .init(name: "size",    value: "\(width)x\(height)"),
            .init(name: "scale",   value: String(scale)),
            .init(name: "maptype", value: "satellite"),
            .init(name: "format",  value: "png"),
            .init(name: "key",     value: APIKeys.googleMapsApiKey)
        ]
        return comps.url
    }
}
