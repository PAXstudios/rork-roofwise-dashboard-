import SwiftUI
import CoreLocation

@MainActor
@Observable
final class MileageTrackerService: NSObject {
    enum AuthState { case notDetermined, authorized, denied }

    // Live tracking state
    var isTracking: Bool = false
    var isPaused: Bool = false
    var currentMiles: Double = 0
    var currentSpeedMph: Double = 0
    var elapsedSeconds: TimeInterval = 0
    var startedAt: Date?
    var authState: AuthState = .notDetermined
    var lastError: String?

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    /// Public live path for map snippet rendering.
    var path: [MileageTripPoint] = []
    var lastCoordinate: CLLocationCoordinate2D?
    private var tickerTask: Task<Void, Never>?
    /// Ignore tiny fluctuations so static phone doesn't accumulate distance.
    private let minMoveMeters: Double = 8

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: authState = .authorized
        case .denied, .restricted: authState = .denied
        default: authState = .notDetermined
        }
    }

    func requestAuth() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard !isTracking else { return }
        if authState == .notDetermined { requestAuth() }
        currentMiles = 0
        currentSpeedMph = 0
        elapsedSeconds = 0
        path = []
        lastLocation = nil
        lastCoordinate = nil
        startedAt = Date()
        isTracking = true
        isPaused = false
        manager.startUpdatingLocation()
        startTicker()
    }

    func pause() {
        guard isTracking, !isPaused else { return }
        isPaused = true
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard isTracking, isPaused else { return }
        isPaused = false
        lastLocation = nil
        manager.startUpdatingLocation()
    }

    func stop() -> (miles: Double, startedAt: Date, endedAt: Date, path: [MileageTripPoint])? {
        guard isTracking, let started = startedAt else { return nil }
        manager.stopUpdatingLocation()
        tickerTask?.cancel()
        tickerTask = nil
        let result = (currentMiles, started, Date(), path)
        isTracking = false
        isPaused = false
        currentMiles = 0
        currentSpeedMph = 0
        elapsedSeconds = 0
        startedAt = nil
        lastLocation = nil
        path = []
        return result
    }

    func cancel() {
        manager.stopUpdatingLocation()
        tickerTask?.cancel()
        tickerTask = nil
        isTracking = false
        isPaused = false
        currentMiles = 0
        currentSpeedMph = 0
        elapsedSeconds = 0
        startedAt = nil
        lastLocation = nil
        path = []
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let s = self, s.isTracking, !s.isPaused, let started = s.startedAt {
                    s.elapsedSeconds = Date().timeIntervalSince(started)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    fileprivate func ingest(_ loc: CLLocation) {
        guard isTracking, !isPaused else { return }
        // Ignore very inaccurate fixes
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 else { return }
        if let last = lastLocation {
            let meters = loc.distance(from: last)
            if meters >= minMoveMeters {
                currentMiles += meters / 1609.344
                lastLocation = loc
                path.append(MileageTripPoint(lat: loc.coordinate.latitude,
                                             lon: loc.coordinate.longitude,
                                             timestamp: loc.timestamp))
                lastCoordinate = loc.coordinate
            }
        } else {
            lastLocation = loc
            path.append(MileageTripPoint(lat: loc.coordinate.latitude,
                                         lon: loc.coordinate.longitude,
                                         timestamp: loc.timestamp))
            lastCoordinate = loc.coordinate
        }
        // m/s -> mph
        currentSpeedMph = max(0, loc.speed) * 2.23694
    }

    fileprivate func handleAuth(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            authState = .authorized
            if isTracking, !isPaused { manager.startUpdatingLocation() }
        case .denied, .restricted:
            authState = .denied
            lastError = "Location permission denied. Enable in Settings to track mileage."
        default:
            authState = .notDetermined
        }
    }
}

extension MileageTrackerService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.ingest(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in self.handleAuth(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.lastError = msg }
    }
}
