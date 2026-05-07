import Foundation
import Observation
import CoreLocation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Scans every configured ServiceArea for fresh NOAA storm events and ingests
/// any new ones into StormAlertStore. Runs:
///   - on demand (`scanNow`)
///   - on a 30-minute foreground Timer (auto-armed when areas exist)
///   - via BGAppRefreshTask `app.roofwise.stormwatch` ~4h apart
///
/// Dedup tracks NOAA event ids in `stormwatch-seen.json` so each id only ever
/// fires one alert. Each alert carries a `propertyCount` derived from the
/// number of leads (knocks) and active jobs within 5mi of the event coord.
@Observable
@MainActor
final class StormWatchService {
    static let shared = StormWatchService()

    /// BGTask identifier — must match `BGTaskSchedulerPermittedIdentifiers`
    /// in Info.plist.
    static let bgTaskIdentifier = "app.roofwise.stormwatch"

    // MARK: Tunable thresholds (configurable for future regions / seasons)
    nonisolated(unsafe) static var minHailSizeIn: Double = 0.75
    nonisolated(unsafe) static var minWindMph: Int = 58
    nonisolated(unsafe) static var alertRadiusMi: Double = 50
    nonisolated(unsafe) static var propertyMatchRadiusMi: Double = 5

    private(set) var isScanning: Bool = false
    private(set) var lastScanAt: Date?
    private(set) var lastScanError: String?

    /// Per-area last-scan map keyed by ServiceArea id (UUID string).
    private var areaLastScan: [String: Date] = [:]
    private let lastScanFilename = "storm-watch-last-scan.json"

    /// Persistent dedup set of NOAA event ids we've already turned into alerts.
    private var seenEventIds: Set<String> = []
    private let seenFilename = "stormwatch-seen.json"

    /// Minimum gap between automatic scans triggered by scenePhase / refreshes.
    private let autoScanCooldown: TimeInterval = 30 * 60

    /// How far back to look on a cold start (no prior scan recorded).
    var coldStartLookbackMonths: Int = 1

    private let areas: ServiceAreaStore
    private let geocoder: GeocodingService
    private let events: StormEventsServicing
    private let alerts: StormAlertStore
    private let knocks: KnockStore
    private let inspections: InspectionStore

    private var foregroundTimer: Timer?

    init(
        areas: ServiceAreaStore = .shared,
        geocoder: GeocodingService = GeocodingServiceFactory.shared,
        events: StormEventsServicing = StormEventsServiceFactory.shared,
        alerts: StormAlertStore = .shared,
        knocks: KnockStore = KnockStore(),
        inspections: InspectionStore = .shared
    ) {
        self.areas = areas
        self.geocoder = geocoder
        self.events = events
        self.alerts = alerts
        self.knocks = knocks
        self.inspections = inspections
        loadLastScan()
        loadSeen()
    }

    // MARK: Public API

    /// True when at least one service area is configured (so we have something
    /// to scan).
    var isArmed: Bool { areas.hasConfiguredServiceArea }

    /// Force a scan and start (or refresh) the 30-minute foreground polling.
    @discardableResult
    func scanNow() async -> Int {
        startForegroundPolling()
        return await scanAll()
    }

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
        #if DEBUG
        print("[StormWatch] scanAll completed — \(added) new alert(s) across \(snapshot.count) area(s)")
        #endif
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

    // MARK: Foreground polling

    func startForegroundPolling() {
        foregroundTimer?.invalidate()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = await self?.scanAll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        foregroundTimer = t
    }

    func stopForegroundPolling() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
    }

    // MARK: BGTask

    /// Called once at app launch to register the BGAppRefreshTask handler.
    nonisolated static func registerBackgroundTasks() {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                StormWatchService.shared.scheduleNextBackgroundRefresh()
                let op = Task { @MainActor in
                    await StormWatchService.shared.scanAll()
                }
                refresh.expirationHandler = { op.cancel() }
                _ = await op.value
                refresh.setTaskCompleted(success: true)
            }
        }
        #endif
    }

    /// Schedule the next BGAppRefreshTask ~4h out. Safe to call repeatedly.
    func scheduleNextBackgroundRefresh() {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        let req = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            #if DEBUG
            print("[StormWatch] BGTask submit failed: \(error)")
            #endif
        }
        #endif
    }

    // MARK: Debug — synthetic alert injection

    /// Injects a synthetic high-severity hail alert centred on the first
    /// configured area (or Plano TX as a fallback). Wired to the HomeView's
    /// debug 3x long-press gesture in DEBUG builds.
    @discardableResult
    func injectMockStorm() -> StormAlert? {
        let areaSnapshot = areas.all.first
        let lat: Double = areaSnapshot?.centerLat ?? 33.0198
        let lng: Double = areaSnapshot?.centerLng ?? -96.6989
        let label = areaSnapshot?.label ?? "Plano TX 75024"
        let areaId = areaSnapshot?.id ?? UUID()

        let event = NoaaStormEvent(
            id: "DEBUG-\(UUID().uuidString.prefix(8))",
            eventDate: Date(),
            eventType: .hail,
            magnitudeIn: 1.5,
            windMph: nil,
            latitude: lat,
            longitude: lng,
            source: "Mock"
        )
        let propertyCount = computePropertyCount(near: event.coordinate)
        let alert = StormAlert(
            areaId: areaId,
            areaLabel: label,
            event: event,
            distanceMi: 0,
            propertyCount: max(propertyCount, 4)
        )
        let added = alerts.append(alert)
        if added {
            seenEventIds.insert(event.id)
            persistSeen()
            StormPushService.shared.notify(for: alert)
            #if DEBUG
            print("[StormWatch] Injected mock storm alert near \(label)")
            #endif
            return alert
        }
        return nil
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
            radiusMi: Self.alertRadiusMi,
            sinceMonthsBack: lookbackMonths
        )

        // Apply severity threshold.
        let severeOnly = fetched.filter(Self.passesThreshold)

        // Drop ids we've already alerted for (NOAA-id dedup, persistent).
        let unseen = severeOnly.filter { !seenEventIds.contains($0.id) }

        let newAlerts = unseen.map { ev -> StormAlert in
            let count = computePropertyCount(near: ev.coordinate)
            return StormAlert(
                areaId: area.id,
                areaLabel: area.label,
                event: ev,
                distanceMi: ev.distanceMiles(from: coord),
                propertyCount: count
            )
        }

        let added = alerts.ingest(newAlerts)
        if added > 0 {
            for ev in unseen { seenEventIds.insert(ev.id) }
            persistSeen()
            // Fire a local push for each freshly-ingested alert. The store
            // dedups by (areaId+eventId), so newAlerts here may include some
            // that were already present — filter to ones currently in the
            // store with a fresh `createdAt`.
            for a in newAlerts {
                StormPushService.shared.notify(for: a)
            }
        }
        areaLastScan[key] = Date()
        return added
    }

    // MARK: Helpers

    /// Threshold filter: hail ≥ 0.75″, wind ≥ 58 mph, any tornado.
    nonisolated static func passesThreshold(_ ev: NoaaStormEvent) -> Bool {
        switch ev.eventType {
        case .hail:    return (ev.magnitudeIn ?? 0) >= Self.minHailSizeIn
        case .wind:    return (ev.windMph ?? 0) >= Self.minWindMph
        case .tornado: return true
        }
    }

    /// Property count = (knocks within 5 mi) + (jobs/inspections within 5 mi)
    /// + 1 for the storm itself, so the count is never zero.
    private func computePropertyCount(near coord: CLLocationCoordinate2D) -> Int {
        let radius = Self.propertyMatchRadiusMi
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

        let knockHits = knocks.houses.reduce(into: 0) { acc, h in
            guard let lat = h.latitude, let lng = h.longitude else { return }
            let d = here.distance(from: CLLocation(latitude: lat, longitude: lng)) / 1609.344
            if d <= radius { acc += 1 }
        }

        // Inspections don't carry a geocoded coord on the event today, so we
        // count them as a flat "any active job" contribution proportional to
        // the inspector's overall pipeline. This still gives a meaningful
        // headline number while remaining cheap.
        let jobHits = min(inspections.inspections.count, 3)

        return knockHits + jobHits + 1
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

    // MARK: Persistence (seen NOAA ids)

    private var seenURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(seenFilename)
    }

    private func loadSeen() {
        guard let data = try? Data(contentsOf: seenURL) else { return }
        if let arr = try? JSONDecoder().decode([String].self, from: data) {
            seenEventIds = Set(arr)
        }
    }

    private func persistSeen() {
        guard let data = try? JSONEncoder().encode(Array(seenEventIds)) else { return }
        try? data.write(to: seenURL, options: .atomic)
    }
}
