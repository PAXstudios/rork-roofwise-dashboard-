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
            source: source,
            eventType: eventType
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
        // Default to a three-year window so hail history is deep enough to drive
        // canvassing decisions, matching the map's default range.
        try await events(near: coord, radiusMi: 50, sinceMonthsBack: 37)
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

// MARK: - Live impl (real multi-year NOAA / NWS history — keyless)
//
// The map's storm overlay is fed from two free, key-less government sources:
//
//   • Hail    — NOAA SWDI NEXRAD Level-III Hail Signal (`nx3hail`). Radar-derived
//               max hail size in inches with complete spatial coverage going back
//               to the 1990s. This is the spine of the "3 years of hail" view.
//   • Tornado — NOAA SWDI NEXRAD Tornado Vortex Signature (`nx3tvs`).
//   • Wind    — Iowa Environmental Mesonet Local Storm Reports (`lsr.geojson`).
//               SWDI has no wind product, so wind uses the ground-truth NWS LSR
//               feed, keyed to the state under the map.
//
// SWDI radar output re-scans a storm cell every few minutes, so the raw feed is
// dense. We collapse it to one pin per ~2.8 mi grid cell per day, keeping the
// worst magnitude. Requests are chunked by year and fetched in parallel; any
// failure degrades quietly so the inspector is never blocked in the field.
//
// (The previous implementation called `ncei.../access/services/data/v1` with
// `dataset=storm-events`, which the service rejects with HTTP 400 "Unsupported
// dataset" — that is why no storm pins ever rendered.)

final class LiveStormEventsService: StormEventsServicing, @unchecked Sendable {
    let isLive = true

    private let session: URLSession

    // Coarse in-memory cache so re-opening the map or nudging the camera doesn't
    // refetch several MB of history every time.
    private struct CacheEntry: Sendable { let key: String; let at: Date; let events: [NoaaStormEvent] }
    private var cache: CacheEntry?
    private let cacheTTL: TimeInterval = 60 * 20   // 20 min

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        cfg.httpAdditionalHeaders = [
            "User-Agent": APIKeys.noaaUserAgent,
            "Accept": "text/csv, application/json, */*"
        ]
        self.session = URLSession(configuration: cfg)
    }

    func events(near coord: CLLocationCoordinate2D,
                radiusMi: Double,
                sinceMonthsBack: Int) async throws -> [NoaaStormEvent] {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let months = max(1, sinceMonthsBack)
        guard let start = cal.date(byAdding: .month, value: -months, to: now) else { return [] }

        // Bounding box around the requested center (miles → degrees).
        let dLat = radiusMi / 69.0
        let dLng = radiusMi / (69.0 * max(0.1, cos(coord.latitude * .pi / 180)))
        let box = BBox(west: coord.longitude - dLng,
                       south: coord.latitude - dLat,
                       east: coord.longitude + dLng,
                       north: coord.latitude + dLat)

        // Cache key: coarse center + radius + months.
        let key = String(format: "%.2f,%.2f,%.0f,%d", coord.latitude, coord.longitude, radiusMi, months)
        if let c = cache, c.key == key, now.timeIntervalSince(c.at) < cacheTTL {
            return c.events.filter { $0.distanceMiles(from: coord) <= radiusMi }
        }

        // Year-sized chunks (most recent first), capped so "All time" can't fan
        // out into dozens of requests.
        let chunks = Self.yearlyChunks(from: start, to: now, maxChunks: 6)

        var raw: [NoaaStormEvent] = []

        // Hail (nx3hail) + tornado (nx3tvs) are bbox-native — fetch per chunk in parallel.
        await withTaskGroup(of: [NoaaStormEvent].self) { group in
            for chunk in chunks {
                group.addTask { await self.fetchSWDI(product: .hail, box: box, chunk: chunk) }
                group.addTask { await self.fetchSWDI(product: .tornado, box: box, chunk: chunk) }
            }
            for await part in group { raw.append(contentsOf: part) }
        }

        // Wind ground-truth via IEM LSR needs the state under the map center.
        if let state = await Self.stateCode(for: coord) {
            await withTaskGroup(of: [NoaaStormEvent].self) { group in
                for chunk in chunks {
                    group.addTask { await self.fetchIEMWind(state: state, box: box, chunk: chunk) }
                }
                for await part in group { raw.append(contentsOf: part) }
            }
        }

        let deduped = Self.dedupe(raw, capped: 1200)
            .filter { $0.distanceMiles(from: coord) <= radiusMi }
            .sorted { $0.eventDate > $1.eventDate }

        cache = CacheEntry(key: key, at: now, events: deduped)
        return deduped
    }

    // MARK: SWDI (radar hail + tornado)

    private nonisolated func fetchSWDI(product: SWDIProduct, box: BBox, chunk: DateChunk) async -> [NoaaStormEvent] {
        let bbox = "\(box.west),\(box.south),\(box.east),\(box.north)"
        let range = "\(Self.swdiStamp(chunk.start)):\(Self.swdiStamp(chunk.end))"
        var comps = URLComponents(string: "https://www.ncei.noaa.gov/swdiws/csv/\(product.path)/\(range)")
        comps?.queryItems = [.init(name: "bbox", value: bbox)]
        guard let url = comps?.url else { return [] }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return Self.parseSWDI(csv: text, product: product)
        } catch {
            print("[StormEventsService] SWDI \(product.path) error: \(error)")
            return []
        }
    }

    /// nx3hail: `ZTIME,WSR_ID,CELL_ID,PROB,SEVPROB,MAXSIZE,LAT,LON`
    /// nx3tvs:  `ZTIME,WSR_ID,CELL_ID,CELL_TYPE,RANGE,AZIMUTH,MAX_SHEAR,MXDV,LAT,LON`
    /// Header + summary rows (returned when a window has zero events) fail the
    /// numeric lat/lon guard and are skipped naturally.
    nonisolated static func parseSWDI(csv: String, product: SWDIProduct) -> [NoaaStormEvent] {
        var out: [NoaaStormEvent] = []
        let latIdx = product.latIndex
        let lonIdx = product.lonIndex
        for raw in csv.split(whereSeparator: \.isNewline) {
            let cols = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count > lonIdx,
                  let lat = Double(cols[latIdx]), let lon = Double(cols[lonIdx]),
                  lat != 0, lon != 0,
                  let date = parseZ(cols[0]) else { continue }

            switch product {
            case .hail:
                guard cols.count > 5, let size = Double(cols[5]), size > 0 else { continue }
                out.append(NoaaStormEvent(id: UUID().uuidString, eventDate: date,
                                          eventType: .hail, magnitudeIn: size, windMph: nil,
                                          latitude: lat, longitude: lon, source: "NOAA"))
            case .tornado:
                out.append(NoaaStormEvent(id: UUID().uuidString, eventDate: date,
                                          eventType: .tornado, magnitudeIn: nil, windMph: nil,
                                          latitude: lat, longitude: lon, source: "NOAA"))
            }
        }
        return out
    }

    // MARK: IEM LSR (ground-truth wind)

    private nonisolated func fetchIEMWind(state: String, box: BBox, chunk: DateChunk) async -> [NoaaStormEvent] {
        var comps = URLComponents(string: "https://mesonet.agron.iastate.edu/geojson/lsr.geojson")
        comps?.queryItems = [
            .init(name: "sts", value: Self.iemStamp(chunk.start)),
            .init(name: "ets", value: Self.iemStamp(chunk.end)),
            .init(name: "states", value: state)
        ]
        guard let url = comps?.url else { return [] }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let decoded = try JSONDecoder().decode(IEMLSRResponse.self, from: data)
            return decoded.features.compactMap { $0.asWindEvent(in: box) }
        } catch {
            print("[StormEventsService] IEM LSR error: \(error)")
            return []
        }
    }

    // MARK: Reverse-geocode the map center → 2-letter state (for IEM)

    nonisolated static func stateCode(for coord: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(loc),
              let state = placemarks.first?.administrativeArea, state.count == 2 else {
            return nil
        }
        return state.uppercased()
    }

    // MARK: Dedupe — collapse dense radar to one pin per cell-day

    nonisolated static func dedupe(_ events: [NoaaStormEvent], capped: Int) -> [NoaaStormEvent] {
        let grid = 0.04   // ~2.8 mi cells
        var best: [String: NoaaStormEvent] = [:]
        let cal = Calendar(identifier: .gregorian)
        for e in events {
            let dayStamp = Int(cal.startOfDay(for: e.eventDate).timeIntervalSince1970 / 86_400)
            let gLat = (e.latitude / grid).rounded()
            let gLon = (e.longitude / grid).rounded()
            let key = "\(e.eventType.rawValue)|\(dayStamp)|\(gLat)|\(gLon)"
            if let existing = best[key] {
                if intensity(e) > intensity(existing) { best[key] = e }
            } else {
                best[key] = e
            }
        }
        let sorted = best.values.sorted { $0.eventDate > $1.eventDate }
        return Array(sorted.prefix(capped))
    }

    private nonisolated static func intensity(_ e: NoaaStormEvent) -> Double {
        switch e.eventType {
        case .hail:    return e.magnitudeIn ?? 0
        case .wind:    return Double(e.windMph ?? 0)
        case .tornado: return 999
        }
    }

    // MARK: Date helpers

    nonisolated static func yearlyChunks(from start: Date, to end: Date, maxChunks: Int) -> [DateChunk] {
        let cal = Calendar(identifier: .gregorian)
        var chunks: [DateChunk] = []
        var cursorEnd = end
        while cursorEnd > start && chunks.count < maxChunks {
            let cursorStart = max(start, cal.date(byAdding: .year, value: -1, to: cursorEnd) ?? start)
            chunks.append(DateChunk(start: cursorStart, end: cursorEnd))
            cursorEnd = cursorStart
        }
        return chunks
    }

    private nonisolated static func swdiStamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    private nonisolated static func iemStamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f.string(from: d)
    }

    nonisolated static func parseZ(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.date(from: s)
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

// MARK: - Geometry + chunk value types

nonisolated struct BBox: Sendable {
    let west: Double
    let south: Double
    let east: Double
    let north: Double

    func contains(lat: Double, lon: Double) -> Bool {
        lon >= west && lon <= east && lat >= south && lat <= north
    }
}

nonisolated struct DateChunk: Sendable {
    let start: Date
    let end: Date
}

nonisolated enum SWDIProduct: Sendable {
    case hail
    case tornado

    var path: String { self == .hail ? "nx3hail" : "nx3tvs" }
    /// Column index of LAT / LON in each product's CSV layout.
    var latIndex: Int { self == .hail ? 6 : 8 }
    var lonIndex: Int { self == .hail ? 7 : 9 }
}

// MARK: - IEM Local Storm Report DTO

private nonisolated struct IEMLSRResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let properties: Props
        let geometry: Geometry

        /// Map a Local Storm Report to a wind `NoaaStormEvent` when it is a
        /// thunderstorm-wind report inside the bbox. Hail and tornado reports are
        /// sourced from SWDI radar instead, so they're skipped here to avoid
        /// double-counting.
        func asWindEvent(in box: BBox) -> NoaaStormEvent? {
            guard geometry.coordinates.count >= 2 else { return nil }
            let lon = geometry.coordinates[0]
            let lat = geometry.coordinates[1]
            guard box.contains(lat: lat, lon: lon) else { return nil }

            let text = (properties.typetext ?? "").uppercased()
            guard text.contains("WND") || text.contains("WIND") else { return nil }

            let mph: Int
            if let m = properties.magnitudeValue, m > 0 {
                mph = Int(m.rounded())
            } else {
                mph = 60   // damage report without a measured gust — nominal severe-ish
            }
            let date = Props.parse(properties.valid) ?? Date()
            return NoaaStormEvent(id: UUID().uuidString, eventDate: date,
                                  eventType: .wind, magnitudeIn: nil, windMph: mph,
                                  latitude: lat, longitude: lon, source: "NWS")
        }
    }

    struct Geometry: Decodable { let coordinates: [Double] }   // [lon, lat]

    struct Props: Decodable {
        let typetext: String?
        let valid: String?
        let magnitudeValue: Double?

        enum CodingKeys: String, CodingKey { case typetext, valid, magf, magnitude }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            typetext = try? c.decode(String.self, forKey: .typetext)
            valid = try? c.decode(String.self, forKey: .valid)
            // IEM reports magnitude either as a numeric `magf` or a (sometimes
            // empty) `magnitude` string — decode defensively.
            if let d = try? c.decode(Double.self, forKey: .magf) {
                magnitudeValue = d
            } else if let s = try? c.decode(String.self, forKey: .magnitude), let d = Double(s) {
                magnitudeValue = d
            } else if let d = try? c.decode(Double.self, forKey: .magnitude) {
                magnitudeValue = d
            } else {
                magnitudeValue = nil
            }
        }

        static func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            for fmt in ["yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm'Z'"] {
                f.dateFormat = fmt
                if let d = f.date(from: s) { return d }
            }
            return nil
        }
    }
}
