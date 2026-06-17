import Foundation
import CoreLocation
import UserNotifications
import UIKit

/// Detects drives in the background via CoreLocation significant-location-change monitoring.
/// When a completed drive is detected (speed > 5mph for > 0.5 miles, then stopped 5+ minutes),
/// posts a local notification asking the user to log it.
@MainActor
@Observable
final class MileageAutoTrackService: NSObject {
    static let shared = MileageAutoTrackService()

    // MARK: Persistent settings

    private let enabledKey = "rw.mileage.autoTrack.enabled.v1"
    private let bufferKey = "rw.mileage.autoTrack.buffer.v1"
    private let lastNotifyIdsKey = "rw.mileage.autoTrack.notifyIds.v1"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }

    /// True while we have at least one location point in the active drive buffer.
    var driveInProgress: Bool { !buffer.isEmpty }
    var lastDetectedMiles: Double = 0
    var lastDetectedAt: Date?
    var lastError: String?
    var authState: MileageTrackerService.AuthState = .notDetermined

    // MARK: Private

    private let manager = CLLocationManager()
    private var buffer: [BufferedPoint] = []
    private var stopCheckTask: Task<Void, Never>?

    /// Drive detection thresholds.
    private let minDriveMiles: Double = 0.5
    private let minSpeedMph: Double = 5
    private let stopGapSeconds: TimeInterval = 5 * 60

    /// True only when the built app actually declares the `location` background mode.
    /// Setting `allowsBackgroundLocationUpdates = true` without it throws an
    /// uncatchable `NSInternalInconsistencyException` and crashes on a real device
    /// (the simulator is more lenient). Gating on the runtime value makes the
    /// activation path crash-proof regardless of how the Info.plist is built.
    private var backgroundLocationModeDeclared: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    // MARK: Init

    override init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) == nil {
            self.isEnabled = false
        } else {
            self.isEnabled = defaults.bool(forKey: enabledKey)
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        // Background updates are only enabled while auto-tracking is ON (see startMonitoring).
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        loadBuffer()
        refreshAuth()
        if isEnabled { startMonitoring() }
    }

    // MARK: Public API

    func toggle(_ on: Bool) {
        isEnabled = on
    }

    func requestAuthorization() {
        // Auto-tracking needs Always for SLC to wake the app in background.
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func requestNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        registerCategory()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Removes any pending detection notifications and clears the active buffer.
    func clearActiveDetection() {
        buffer.removeAll()
        persistBuffer()
        stopCheckTask?.cancel()
        stopCheckTask = nil
    }

    // MARK: Lifecycle

    private func startMonitoring() {
        refreshAuth()
        registerCategory()

        print("[AutoTracking] activating, auth=\(manager.authorizationStatus.rawValue), slcAvailable=\(CLLocationManager.significantLocationChangeMonitoringAvailable()), bgLocationMode=\(backgroundLocationModeDeclared)")

        // Only opt-in to background delivery when the user has enabled auto-tracking AND
        // granted Always authorization. SLC alone wakes the app from suspended state, but
        // `allowsBackgroundLocationUpdates` is required to keep receiving updates while
        // backgrounded if we ever escalate to standard updates.
        //
        // CRITICAL: this property MUST only be set true when the `location` background
        // mode is actually declared, otherwise iOS throws and crashes on a real device.
        if manager.authorizationStatus == .authorizedAlways, backgroundLocationModeDeclared {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }

        // Significant-location-change monitoring isn't available on every device.
        // Calling it where unsupported is a no-op for delivery, but we guard anyway
        // and surface a clear message rather than silently doing nothing.
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            lastError = "Background drive detection isn't available on this device."
            print("[AutoTracking] SLC monitoring unavailable on this device")
            return
        }
        manager.startMonitoringSignificantLocationChanges()
    }

    private func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        stopCheckTask?.cancel()
        stopCheckTask = nil
        buffer.removeAll()
        persistBuffer()
    }

    private func refreshAuth() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: authState = .authorized
        case .denied, .restricted: authState = .denied
        default: authState = .notDetermined
        }
    }

    // MARK: Drive detection

    fileprivate func ingest(_ loc: CLLocation) {
        guard isEnabled else { return }
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }

        let point = BufferedPoint(lat: loc.coordinate.latitude,
                                  lon: loc.coordinate.longitude,
                                  timestamp: loc.timestamp,
                                  speedMps: max(0, loc.speed))

        if let last = buffer.last {
            let gap = point.timestamp.timeIntervalSince(last.timestamp)
            if gap >= stopGapSeconds {
                // Driver stopped — finalize previous segment, then start fresh.
                finalizeBufferIfQualifies()
                buffer = [point]
            } else {
                buffer.append(point)
            }
        } else {
            buffer = [point]
        }
        persistBuffer()
        scheduleStopCheck()
    }

    /// While in foreground we can run a timer; if app is suspended this won't fire,
    /// but the next SLC delivery will catch the gap and finalize.
    private func scheduleStopCheck() {
        stopCheckTask?.cancel()
        stopCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(310))
            guard let self, !Task.isCancelled else { return }
            if let last = self.buffer.last,
               Date().timeIntervalSince(last.timestamp) >= self.stopGapSeconds {
                self.finalizeBufferIfQualifies()
                self.buffer.removeAll()
                self.persistBuffer()
            }
        }
    }

    private func finalizeBufferIfQualifies() {
        guard buffer.count >= 2 else { return }

        // Total distance (miles) from successive points.
        var meters: Double = 0
        for i in 1..<buffer.count {
            let a = buffer[i - 1]
            let b = buffer[i]
            let la = CLLocation(latitude: a.lat, longitude: a.lon)
            let lb = CLLocation(latitude: b.lat, longitude: b.lon)
            meters += lb.distance(from: la)
        }
        let miles = meters / 1609.344

        // Average speed across the trip in mph.
        guard let first = buffer.first, let last = buffer.last else { return }
        let elapsed = max(1, last.timestamp.timeIntervalSince(first.timestamp))
        let avgMph = (meters / elapsed) * 2.23694

        // Either average drive speed or any sample showed a real drive.
        let anySpeedSample = buffer.contains { ($0.speedMps * 2.23694) >= minSpeedMph }

        guard miles >= minDriveMiles, (avgMph >= minSpeedMph || anySpeedSample) else { return }

        lastDetectedMiles = miles
        lastDetectedAt = last.timestamp

        let trip = PendingAutoTrip(
            miles: miles,
            startedAt: first.timestamp,
            endedAt: last.timestamp,
            path: buffer.map { MileageTripPoint(lat: $0.lat, lon: $0.lon, timestamp: $0.timestamp) }
        )
        AutoTripInbox.shared.enqueue(trip)
        sendDetectionNotification(for: trip)
    }

    // MARK: Notifications

    static let categoryId = "rw.mileage.autoTrip"
    static let logActionId = "rw.mileage.autoTrip.log"
    static let dismissActionId = "rw.mileage.autoTrip.dismiss"
    static let userInfoTripIdKey = "tripId"

    private func registerCategory() {
        let log = UNNotificationAction(identifier: Self.logActionId,
                                       title: "Yes — Log It",
                                       options: [.foreground])
        let dismiss = UNNotificationAction(identifier: Self.dismissActionId,
                                           title: "Dismiss",
                                           options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.categoryId,
                                              actions: [log, dismiss],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func sendDetectionNotification(for trip: PendingAutoTrip) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "RoofWise"
            content.body = String(format: "Looks like you just drove %.1f miles. Add to mileage log?", trip.miles)
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            content.userInfo = [Self.userInfoTripIdKey: trip.id.uuidString]
            let req = UNNotificationRequest(identifier: trip.id.uuidString,
                                            content: content,
                                            trigger: nil)
            center.add(req, withCompletionHandler: nil)
        }
    }

    // MARK: Persistence

    private struct BufferedPoint: Codable {
        let lat: Double
        let lon: Double
        let timestamp: Date
        let speedMps: Double
    }

    private func persistBuffer() {
        if let data = try? JSONEncoder().encode(buffer) {
            UserDefaults.standard.set(data, forKey: bufferKey)
        }
    }

    private func loadBuffer() {
        guard let data = UserDefaults.standard.data(forKey: bufferKey),
              let decoded = try? JSONDecoder().decode([BufferedPoint].self, from: data) else { return }
        buffer = decoded
    }
}

extension MileageAutoTrackService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let snapshot = locations
        Task { @MainActor in
            for loc in snapshot { self.ingest(loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.refreshAuth()
            // Re-apply background flag now that auth may have escalated to Always.
            // Guard on the declared background mode — setting this without the
            // `location` UIBackgroundMode crashes on a real device.
            if self.isEnabled, manager.authorizationStatus == .authorizedAlways, self.backgroundLocationModeDeclared {
                manager.allowsBackgroundLocationUpdates = true
                manager.showsBackgroundLocationIndicator = true
            } else if !self.isEnabled {
                manager.allowsBackgroundLocationUpdates = false
                manager.showsBackgroundLocationIndicator = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.lastError = msg }
    }
}

// MARK: - Detected trip inbox

struct PendingAutoTrip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let miles: Double
    let startedAt: Date
    let endedAt: Date
    let path: [MileageTripPoint]
}

/// Holds detected drives that the user can confirm into the mileage log.
@MainActor
@Observable
final class AutoTripInbox {
    static let shared = AutoTripInbox()

    private let key = "rw.mileage.autoTrack.inbox.v1"
    var pending: [PendingAutoTrip] = []
    var presented: PendingAutoTrip?

    private init() { load() }

    func enqueue(_ trip: PendingAutoTrip) {
        pending.insert(trip, at: 0)
        persist()
    }

    func remove(id: UUID) {
        pending.removeAll { $0.id == id }
        persist()
    }

    func find(idString: String) -> PendingAutoTrip? {
        guard let uuid = UUID(uuidString: idString) else { return nil }
        return pending.first { $0.id == uuid }
    }

    func presentIfNeeded(idString: String) {
        if let trip = find(idString: idString) {
            presented = trip
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PendingAutoTrip].self, from: data) else { return }
        pending = decoded
    }
}
