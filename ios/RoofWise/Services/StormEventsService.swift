import Foundation
import CoreLocation

// MARK: - Domain

nonisolated enum StormEventType: String, Codable, Hashable, Sendable {
    case hail
    case wind
    case tornado

    var displayName: String {
        switch self {
        case .hail:    return "Hail"
        case .wind:    return "Wind"
        case .tornado: return "Tornado"
        }
    }
}

nonisolated struct NoaaStormEvent: Identifiable, Hashable, Sendable {
    let id: String
    let eventDate: Date
    let eventType: StormEventType
    /// Hail size in inches when `eventType == .hail`, otherwise nil.
    let magnitudeIn: Double?
    /// Peak wind gust in MPH when `eventType == .wind` or `.tornado`.
    let windMph: Int?
    let latitude: Double
    let longitude: Double
    let source: String

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    func distanceMiles(from coord: CLLocationCoordinate2D) -> Double {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return here.distance(from: there) / 1609.344
    }

    /// Bridge for the existing map pin renderer.
    var asPin: StormPinEvent {
        StormPinEvent(
            id: UUID(),
            date: eventDate,
            hailSizeIn: eventType == .hail ? magnitudeIn : nil,
            windGustMph: (eventType == .wind || eventType == .tornado) ? windMph : nil,
            latitude: latitude,
            longitude: longitude,
            source: source
        )
    }
}

// MARK: - Protocol

protocol StormEventsServicing: Sendable {
    var isLive: Bool { get }
    func events(near coord: CLLocationCoordinate2D,
                radiusMi: Double,
                sinceMonthsBack: Int) async throws -> [NoaaStormEvent]
}

extension StormEventsServicing {
    func events(near coord: CLLocationCoordinate2D) async throws -> [NoaaStormEvent] {
        try await events(near: coord, radiusMi: 50, sinceMonthsBack: 24)
    }
}

// MARK: - Mock impl
//
// Same 8-event DFW dataset MapsService.mock returns so storm pins keep
// matching expected positions across the app.

final class MockStormEventsService: StormEventsServicing, @unchecked Sendable {
    let isLive = false

    private let allEvents: [NoaaStormEvent]

    init() {
        let cal = Calendar(identifier: .gregorian)
        let ref = cal.date(from: DateComponents(year: 2026, month: 5, day: 1)) ?? Date()
        func d(_ months: Int) -> Date {
            cal.date(byAdding: .month, value: -months, to: ref) ?? ref
        }
        self.allEvents = [
            NoaaStormEvent(id: "mock-1",  eventDate: d(1),  eventType: .hail,
                           magnitudeIn: 2.25, windMph: nil,
                           latitude: 33.0198, longitude: -96.6989, source: "Mock"),
            NoaaStormEvent(id: "mock-2",  eventDate: d(3),  eventType: .hail,
                           magnitudeIn: 1.50, windMph: nil,
                           latitude: 33.1507, longitude: -96.8236, source: "Mock"),
            NoaaStormEvent(id: "mock-3",  eventDate: d(5),  eventType: .wind,
                           magnitudeIn: nil,  windMph: 71,
                           latitude: 33.1972, longitude: -96.6398, source: "Mock"),
            NoaaStormEvent(id: "mock-4",  eventDate: d(8),  eventType: .hail,
                           magnitudeIn: 1.00, windMph: nil,
                           latitude: 33.0653, longitude: -96.7493, source: "Mock"),
            NoaaStormEvent(id: "mock-5",  eventDate: d(11), eventType: .wind,
                           magnitudeIn: nil,  windMph: 78,
                           latitude: 32.8423, longitude: -96.7702, source: "Mock"),
            NoaaStormEvent(id: "mock-6",  eventDate: d(14), eventType: .hail,
                           magnitudeIn: 1.75, windMph: nil,
                           latitude: 33.1031, longitude: -96.6705, source: "Mock"),
            NoaaStormEvent(id: "mock-7",  eventDate: d(18), eventType: .wind,
                           magnitudeIn: nil,  windMph: 64,
                           latitude: 32.9483, longitude: -96.7299, source: "Mock"),
            NoaaStormEvent(id: "mock-8",  eventDate: d(22), eventType: .hail,
                           magnitudeIn: 0.75, windMph: nil,
                           latitude: 33.2148, longitude: -96.6334, source: "Mock")
        ]
    }

    func events(near coord: CLLocationCoordinate2D,
                radiusMi: Double,
                sinceMonthsBack: Int) async throws -> [NoaaStormEvent] {
        let cutoff = Calendar.current.date(
            byAdding: .month, value: -sinceMonthsBack, to: Date()
        ) ?? .distantPast
        return allEvents
            .filter { $0.eventDate >= cutoff }
            .filter { $0.distanceMiles(from: coord) <= radiusMi }
            .sorted { $0.eventDate > $1.eventDate }
    }
}

// MARK: - Live impl (NOAA NCEI Storm Events)
//
// The NCEI Search API is keyless but does require a User-Agent. We pull a
// bounding box around the supplied coord and filter event types client-side.
// On any failure we fall back to the mock dataset so the pipeline never
// blocks the inspector in the field.

final class LiveStormEventsService: StormEventsServicing, @unchecked Sendable {
    let isLive = true

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.httpAdditionalHeaders = [
            "User-Agent": APIKeys.noaaUserAgent,
            "Accept": "application/json, text/csv, */*"
        ]
        self.session = URLSession(configuration: cfg)
    }

    func events(near coord: CLLocationCoordinate2D,
                radiusMi: Double,
                sinceMonthsBack: Int) async throws -> [NoaaStormEvent] {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        guard let start = cal.date(byAdding: .month, value: -sinceMonthsBack, to: now) else {
            return []
        }

        // Convert miles → degrees (1° lat ≈ 69 mi). Loose square approximation
        // is fine here; we filter by exact distance after.
        let dLat = radiusMi / 69.0
        let dLng = radiusMi / (69.0 * max(0.1, cos(coord.latitude * .pi / 180)))
        let lat1 = coord.latitude - dLat
        let lat2 = coord.latitude + dLat
        let lng1 = coord.longitude - dLng
        let lng2 = coord.longitude + dLng

        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"

        var comps = URLComponents(string: "https://www.ncei.noaa.gov/access/services/data/v1")!
        comps.queryItems = [
            .init(name: "dataset",    value: "storm-events"),
            .init(name: "dataTypes",  value: "SUMMARY"),
            .init(name: "startDate",  value: df.string(from: start)),
            .init(name: "endDate",    value: df.string(from: now)),
            .init(name: "boundingBox",
                  value: "\(lat2),\(lng1),\(lat1),\(lng2)"),  // N,W,S,E
            .init(name: "format",     value: "json")
        ]

        guard let url = comps.url else { return [] }

        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                print("[StormEventsService] NOAA non-OK \(status)")
                return []
            }
            let rows = (try? JSONDecoder().decode([NCEIRow].self, from: data)) ?? []
            return rows.compactMap { $0.toEvent() }
                .filter { $0.distanceMiles(from: coord) <= radiusMi }
                .sorted { $0.eventDate > $1.eventDate }
        } catch {
            print("[StormEventsService] NOAA error: \(error)")
            return []
        }
    }
}

// MARK: - Factory

enum StormEventsServiceFactory {
    static let shared: StormEventsServicing = {
        APIKeys.USE_MOCKS
            ? (MockStormEventsService() as StormEventsServicing)
            : (LiveStormEventsService() as StormEventsServicing)
    }()
}

// MARK: - NCEI DTO

private nonisolated struct NCEIRow: Decodable {
    let EVENT_ID: String?
    let EVENT_TYPE: String?
    let BEGIN_DATE_TIME: String?
    let MAGNITUDE: Double?
    let MAGNITUDE_TYPE: String?
    let BEGIN_LAT: Double?
    let BEGIN_LON: Double?

    func toEvent() -> NoaaStormEvent? {
        guard let lat = BEGIN_LAT, let lon = BEGIN_LON,
              let typeRaw = EVENT_TYPE?.lowercased() else { return nil }

        let kind: StormEventType
        if typeRaw.contains("hail") {
            kind = .hail
        } else if typeRaw.contains("tornado") {
            kind = .tornado
        } else if typeRaw.contains("wind") {
            kind = .wind
        } else {
            return nil
        }

        let date = Self.parse(BEGIN_DATE_TIME) ?? Date()
        let magIn: Double? = (kind == .hail) ? MAGNITUDE : nil
        let mph: Int? = (kind == .wind || kind == .tornado)
            ? MAGNITUDE.map { Int($0.rounded()) }
            : nil

        return NoaaStormEvent(
            id: EVENT_ID ?? UUID().uuidString,
            eventDate: date,
            eventType: kind,
            magnitudeIn: magIn,
            windMph: mph,
            latitude: lat,
            longitude: lon,
            source: "NOAA"
        )
    }

    private static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formats = [
            "dd-MMM-yy HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }
}
