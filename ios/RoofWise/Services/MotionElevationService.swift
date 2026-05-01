import SwiftUI
import CoreMotion
import CoreLocation

@Observable
final class MotionElevationService: NSObject {
    var pitchDegrees: Double = 22.6
    var elevationFeet: Double = 589
    var hasReal: Bool = false

    private let motion = CMMotionManager()
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        startMotion()
        startLocation()
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        location.stopUpdatingLocation()
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            // Camera tilt vs vertical: 0° = aiming horizon, 90° = aiming straight up.
            // Compute angle between -z axis and gravity.
            let angle = atan2(sqrt(g.x * g.x + g.y * g.y), abs(g.z)) * 180.0 / .pi
            self.pitchDegrees = max(0, min(80, angle))
            self.hasReal = true
        }
    }

    private func startLocation() {
        let status = location.authorizationStatus
        if status == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways || status == .notDetermined {
            location.startUpdatingLocation()
        }
    }

    /// Pitch in roof X:12 format (rise per 12" of run)
    var pitchRatioString: String {
        let radians = pitchDegrees * .pi / 180.0
        let rise = tan(radians) * 12.0
        let rounded = max(0, min(24, Int(rise.rounded())))
        return "\(rounded):12"
    }
}

extension MotionElevationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let altitude = locations.last?.altitude else { return }
        let feet = altitude * 3.28084
        Task { @MainActor in
            self.elevationFeet = feet
            self.hasReal = true
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }
}
