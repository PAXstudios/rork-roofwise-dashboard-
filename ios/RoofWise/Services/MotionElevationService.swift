import SwiftUI
import CoreMotion
import CoreLocation

@Observable
final class MotionElevationService: NSObject {
    var pitchDegrees: Double = 22.6
    var rollDegrees: Double = 0
    var elevationFeet: Double = 589
    var hasReal: Bool = false

    /// Optimal capture window for roof inspection (camera tilted up at the roof plane).
    /// 25–55° captures most residential roof slopes without excessive perspective distortion.
    static let optimalPitchRange: ClosedRange<Double> = 25...55
    static let acceptablePitchRange: ClosedRange<Double> = 15...65

    enum TiltQuality { case optimal, acceptable, tooLow, tooHigh }

    var tiltQuality: TiltQuality {
        if Self.optimalPitchRange.contains(pitchDegrees) { return .optimal }
        if Self.acceptablePitchRange.contains(pitchDegrees) {
            return pitchDegrees < Self.optimalPitchRange.lowerBound ? .tooLow : .tooHigh
        }
        return pitchDegrees < Self.acceptablePitchRange.lowerBound ? .tooLow : .tooHigh
    }

    var tiltHint: String {
        switch tiltQuality {
        case .optimal:    return "Hold steady — optimal angle"
        case .acceptable: return pitchDegrees < Self.optimalPitchRange.lowerBound
                                ? "Tilt up slightly"
                                : "Tilt down slightly"
        case .tooLow:     return "Tilt up — aim at the roof"
        case .tooHigh:    return "Tilt down — too steep"
        }
    }

    /// 0 = perfectly level, 1 = max roll/tilt off-axis (>20°).
    var rollMagnitude: Double {
        min(1, abs(rollDegrees) / 20.0)
    }

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
            // Left/right roll about the camera axis. 0 = phone held with top edge up.
            // Positive = right side down.
            let roll = atan2(g.x, -g.y) * 180.0 / .pi
            self.rollDegrees = max(-45, min(45, roll))
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
