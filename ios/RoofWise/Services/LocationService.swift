import Foundation
import Observation
import CoreLocation

/// App-wide location provider. Requests When-In-Use authorization once and
/// publishes the latest coordinate plus a reverse-geocoded "City, ST" label.
/// Used by the home weather tile and any view that needs the user's location.
@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    /// Latest known coordinate, or nil until the first fix arrives.
    var coordinate: CLLocationCoordinate2D?
    /// Reverse-geocoded "City, ST" label for `coordinate`, or nil until resolved.
    var placeLabel: String?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var didStart = false
    private var lastGeocodedAt: Date = .distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    var isDeniedOrRestricted: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Request authorization (if needed) and begin receiving updates. Safe to
    /// call repeatedly — only the first call wires things up.
    func start() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            manager.startUpdatingLocation()
        default:
            break
        }
        didStart = true
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.coordinate = loc.coordinate
            self.reverseGeocodeIfNeeded(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Non-fatal: callers fall back to a default coordinate.
    }

    /// Reverse-geocode at most once every 30s to avoid hammering the geocoder.
    private func reverseGeocodeIfNeeded(_ loc: CLLocation) {
        guard Date().timeIntervalSince(lastGeocodedAt) > 30 || placeLabel == nil else { return }
        lastGeocodedAt = Date()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self, let p = placemarks?.first else { return }
            let city = p.locality ?? p.subAdministrativeArea ?? p.name ?? ""
            let state = p.administrativeArea ?? ""
            let label = [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
            Task { @MainActor in
                if !label.isEmpty { self.placeLabel = label }
            }
        }
    }
}
