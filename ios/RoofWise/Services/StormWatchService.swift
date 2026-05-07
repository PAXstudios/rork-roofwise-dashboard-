import Foundation
import Observation
import CoreLocation

/// Scans every configured ServiceArea for fresh NOAA storm events and ingests
/// any new ones into StormAlertStore. Tracks per-area "last scan" timestamps
/// so each scan only surfaces events newer than the previous run.
@Observable
@MainActor
final class StormWatchService {
    static let shared = StormWatchService()

    private(set) var isScanning: Bool = false
    private(set) var lastScanAt: Date?
    private(set) var lastScanError: String?

    /// Per-area last-scan map keyed by ServiceArea id (UUID string).
    private var areaLastScan: [String: Date] = [:]
    private let lastScanFilename = "storm-watch-last-scan.json"

    /// Minimum gap between automatic scans triggered by scenePhase / refreshes.
    private let autoScanCooldown: TimeInterval = 30 * 60

    /// Default search radius around an area centroid (miles).
    var radiusMi: Double = 25

    /// How far back to look on a cold start (no prior scan recorded).
    var coldStartLookbackMonths: Int = 1

    private let areas: ServiceAreaStore
    private let geocoder: GeocodingService
    private let events: StormEventsServicing
    private let alerts: StormAlertStore
    private let activity: ActivityStore?

    init(
        areas: ServiceAreaStore = .shared,
        geocoder: GeocodingService = GeocodingServiceFactory.shared,
        events: StormEventsServicing = StormEventsServiceFactory.shared,
        alerts: StormAlertStore = .shared,
        activity: ActivityStore? = nil
    ) {
        self.areas = areas
        self.geocoder = geocoder
        self.events = events
        self.alerts = alerts
        self.activity = activity
        loadLastScan()
    }

    // MARK: Public API

    /// True when at least one service area is configured (so we have something
    /// to scan).
    var isArmed: Bool { areas.hasConfiguredServiceArea }

    /// Auto-scan only if we haven't run in `autoScanCooldown` seconds.
    @discardableResult
    func scanIfDue() async -> Int {
        guard isArmed else { return 0 }
        if let last = lastScanAt, Date().timeIntervalSince(last) < autoScanCooldown {
            return 0
        }
        return await scanAll()
    }

    /// Force a scan across every configured area. Returns the number of new
    /// alerts ingested.
    @discardableResult
    func scanAll() async -> Int {
        guard !isScanning else { return 0 }
        isScanning = true
        lastScanError = nil
        defer { isScanning = false }

        let snapshot = areas.all
        guard !snapshot.isEmpty else {
            lastScanAt = Date()
            return 0
        }

        var added = 0
        for area in snapshot {
            do {
                added += try await scan(area: area)
            } catch {
                lastScanError = error.localizedDescription
            }
        }

        lastScanAt = Date()
        persistLastScan()
        return added
    }

    /// Scan a single area on demand (used right after the user adds one).
    @discardableResult
    func scan(areaId: UUID) async -> Int {
        guard let area = areas.all.first(where: { $0.id == areaId }) else { return 0 }
        let n = (try? await scan(area: area)) ?? 0
        lastScanAt = Date()
        persistLastScan()
        return n
    }

    // MARK: Core scan

    private func scan(area: ServiceArea) async throws -> Int {
        // Resolve a coordinate. Prefer the cached centroid, otherwise geocode
        // the label on the fly (best-effort).
        let coord: CLLocationCoordinate2D
        if let lat = area.centerLat, let lng = area.centerLng {
            coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let resolved = try? await geocoder.geocode(area.label) {
            coord = resolved
        } else {
            return 0
        }

        let key = area.id.uuidString
        let lookbackMonths: Int
        if let last = areaLastScan[key] {
            // Pad lookback so we don't miss late-publishing NOAA rows that
            // straddle the previous scan window.
            let monthsSince = Int(ceil(Date().timeIntervalSince(last) / (60 * 60 * 24 * 30)))
            lookbackMonths = max(1, monthsSince + 1)
        } else {
            lookbackMonths = coldStartLookbackMonths
        }

        let fetched = try await events.events(
            near: coord,
            radiusMi: radiusMi,
            sinceMonthsBack: lookbackMonths
        )

        // Only events newer than the last scan are alert-worthy. On cold start
        // we surface everything in the lookback window so the inspector sees
        // historical relevance immediately.
        let cutoff = areaLastScan[key]
        let fresh = fetched.filter { ev in
            guard let cutoff else { return true }
            return ev.eventDate > cutoff
        }

        let newAlerts = fresh.map { ev in
            StormAlert(
                areaId: area.id,
                areaLabel: area.label,
                event: ev,
                distanceMi: ev.distanceMiles(from: coord)
            )
        }

        let added = alerts.ingest(newAlerts)
        areaLastScan[key] = Date()
        return added
    }

    // MARK: Persistence (last-scan map)

    private var lastScanURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(lastScanFilename)
    }

    private func loadLastScan() {
        guard let data = try? Data(contentsOf: lastScanURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let map = try? dec.decode([String: Date].self, from: data) {
            areaLastScan = map
            lastScanAt = map.values.max()
        }
    }

    private func persistLastScan() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(areaLastScan) else { return }
        try? data.write(to: lastScanURL, options: .atomic)
    }
}
