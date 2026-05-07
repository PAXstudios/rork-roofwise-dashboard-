import Foundation
import CoreLocation

// MARK: - Map domain types

nonisolated struct AddressSuggestion: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), title: String, subtitle: String, latitude: Double, longitude: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var fullAddress: String { "\(title) · \(subtitle)" }
}

nonisolated struct StormPinEvent: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let hailSizeIn: Double?
    let windGustMph: Int?
    let latitude: Double
    let longitude: Double
    let source: String   // "NOAA" or "Mock"

    init(id: UUID = UUID(),
         date: Date,
         hailSizeIn: Double? = nil,
         windGustMph: Int? = nil,
         latitude: Double,
         longitude: Double,
         source: String) {
        self.id = id
        self.date = date
        self.hailSizeIn = hailSizeIn
        self.windGustMph = windGustMph
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var isHail: Bool { hailSizeIn != nil }

    var headline: String {
        if let h = hailSizeIn { return String(format: "%.2f\" Hail", h) }
        if let w = windGustMph { return "\(w) mph Wind" }
        return "Storm"
    }
}

// MARK: - Service protocol

protocol MapsService {
    var isLive: Bool { get }
    func suggestAddresses(query: String) async -> [AddressSuggestion]
    func recentStorms() async -> [StormPinEvent]
}

@MainActor
enum MapsServiceFactory {
    /// Live data (NOAA SPC + OSM Nominatim) is free and key-less, so we go live
    /// whenever USE_MOCKS is off — independent of whether Google Maps SDK is wired.
    static func make() -> MapsService {
        APIKeys.USE_MOCKS ? MockMapsService() : LiveMapsService()
    }
}

// MARK: - Mock implementation

final class MockMapsService: MapsService {
    let isLive = false

    private let addresses: [AddressSuggestion]
    private let storms: [StormPinEvent]

    init() {
        self.addresses = [
            AddressSuggestion(title: "1247 Oakridge Ln",  subtitle: "Plano, TX 75025",
                              latitude: 33.0653, longitude: -96.7493),
            AddressSuggestion(title: "445 Pine Lane",     subtitle: "Frisco, TX 75034",
                              latitude: 33.1507, longitude: -96.8236),
            AddressSuggestion(title: "12 Ridge Vista",    subtitle: "Allen, TX 75013",
                              latitude: 33.1031, longitude: -96.6705),
            AddressSuggestion(title: "88 Maple Cove",     subtitle: "McKinney, TX 75070",
                              latitude: 33.1972, longitude: -96.6398),
            AddressSuggestion(title: "2210 Custer Pkwy",  subtitle: "Dallas, TX 75206",
                              latitude: 32.8423, longitude: -96.7702)
        ]

        // Deterministic 8-event storm window across the past 24 months,
        // anchored to a fixed reference date so previews stay stable.
        let cal = Calendar(identifier: .gregorian)
        let ref = cal.date(from: DateComponents(year: 2026, month: 5, day: 1)) ?? Date()
        func d(_ months: Int) -> Date {
            cal.date(byAdding: .month, value: -months, to: ref) ?? ref
        }
        self.storms = [
            StormPinEvent(date: d(1),  hailSizeIn: 2.25, latitude: 33.0198, longitude: -96.6989, source: "Mock"),
            StormPinEvent(date: d(3),  hailSizeIn: 1.50, latitude: 33.1507, longitude: -96.8236, source: "Mock"),
            StormPinEvent(date: d(5),  windGustMph: 71, latitude: 33.1972, longitude: -96.6398, source: "Mock"),
            StormPinEvent(date: d(8),  hailSizeIn: 1.00, latitude: 33.0653, longitude: -96.7493, source: "Mock"),
            StormPinEvent(date: d(11), windGustMph: 78, latitude: 32.8423, longitude: -96.7702, source: "Mock"),
            StormPinEvent(date: d(14), hailSizeIn: 1.75, latitude: 33.1031, longitude: -96.6705, source: "Mock"),
            StormPinEvent(date: d(18), windGustMph: 64, latitude: 32.9483, longitude: -96.7299, source: "Mock"),
            StormPinEvent(date: d(22), hailSizeIn: 0.75, latitude: 33.2148, longitude: -96.6334, source: "Mock")
        ]
    }

    func suggestAddresses(query: String) async -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return addresses }
        return addresses.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func recentStorms() async -> [StormPinEvent] { storms }
}

// MARK: - Live implementation (Phase 4C — free public APIs, no key required)
//
//  Geocoding : OpenStreetMap Nominatim   (User-Agent required by policy)
//  Storms    : NOAA SPC daily reports    (filtered hail + wind CSVs)
//
//  Both endpoints are HTTPS so default ATS is fine. The fallback mock is reused
//  whenever a request fails so the map never goes empty in the field.

final class LiveMapsService: MapsService, @unchecked Sendable {
    let isLive = true

    private let session: URLSession
    private let fallback = MockMapsService()

    // Tiny in-memory caches so we don't hammer NOAA / Nominatim while the user
    // pans the map or types into the address picker.
    private var stormCache: (date: Date, events: [StormPinEvent])?
    private var addressCache: [String: [AddressSuggestion]] = [:]
    private let cacheTTL: TimeInterval = 60 * 30   // 30 min

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

    // MARK: Geocoding (OSM Nominatim)

    func suggestAddresses(query: String) async -> [AddressSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return await fallback.suggestAddresses(query: "") }

        let key = trimmed.lowercased()
        if let hit = addressCache[key] { return hit }

        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comps.queryItems = [
            .init(name: "q", value: trimmed),
            .init(name: "format", value: "jsonv2"),
            .init(name: "limit", value: "6"),
            .init(name: "addressdetails", value: "1"),
            .init(name: "countrycodes", value: "us")
        ]
        guard let url = comps.url else { return await fallback.suggestAddresses(query: trimmed) }

        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return await fallback.suggestAddresses(query: trimmed)
            }
            let raw = try JSONDecoder().decode([NominatimRow].self, from: data)
            let mapped = raw.compactMap { $0.toSuggestion() }
            let result = mapped.isEmpty
                ? await fallback.suggestAddresses(query: trimmed)
                : mapped
            addressCache[key] = result
            return result
        } catch {
            return await fallback.suggestAddresses(query: trimmed)
        }
    }

    // MARK: Storms (NOAA SPC daily filtered reports)

    func recentStorms() async -> [StormPinEvent] {
        if let c = stormCache, Date().timeIntervalSince(c.date) < cacheTTL {
            return c.events
        }

        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        // SPC publishes daily reports — pull a 30-day rolling window.
        let days: [Date] = (1...30).compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }

        var events: [StormPinEvent] = []
        await withTaskGroup(of: [StormPinEvent].self) { group in
            for day in days {
                group.addTask { [self] in await fetchSPCDay(day) }
            }
            for await chunk in group { events.append(contentsOf: chunk) }
        }

        if events.isEmpty {
            // NOAA unreachable — keep the deterministic mock dataset so the map
            // still tells a story instead of going blank.
            let mock = await fallback.recentStorms()
            stormCache = (Date(), mock)
            return mock
        }

        // Sort newest first, cap at a sane number for rendering.
        let sorted = events.sorted { $0.date > $1.date }
        let capped = Array(sorted.prefix(400))
        stormCache = (Date(), capped)
        return capped
    }

    private func fetchSPCDay(_ day: Date) async -> [StormPinEvent] {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyMMdd"
        let stamp = fmt.string(from: day)

        async let hail = fetchSPCCSV(
            url: URL(string: "https://www.spc.noaa.gov/climo/reports/\(stamp)_rpts_filtered_hail.csv")!,
            day: day,
            kind: .hail
        )
        async let wind = fetchSPCCSV(
            url: URL(string: "https://www.spc.noaa.gov/climo/reports/\(stamp)_rpts_filtered_wind.csv")!,
            day: day,
            kind: .wind
        )
        return (await hail) + (await wind)
    }

    nonisolated enum SPCKind { case hail, wind }

    private func fetchSPCCSV(url: URL, day: Date, kind: SPCKind) async -> [StormPinEvent] {
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return Self.parseSPC(csv: text, day: day, kind: kind)
        } catch {
            return []
        }
    }

    /// SPC filtered CSV columns:
    ///   hail: Time,Size,Location,County,State,Lat,Lon,Comments
    ///   wind: Time,Speed,Location,County,State,Lat,Lon,Comments
    /// `Size` is hail size in hundredths of inch (e.g. "100" = 1.00").
    /// `Speed` is MPH or "UNK".
    nonisolated static func parseSPC(csv: String, day: Date, kind: SPCKind) -> [StormPinEvent] {
        var out: [StormPinEvent] = []
        let rows = csv.split(whereSeparator: \.isNewline)
        for (idx, raw) in rows.enumerated() {
            if idx == 0 { continue }                       // header
            let cols = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 7 else { continue }
            guard let lat = Double(cols[5].trimmingCharacters(in: .whitespaces)),
                  let lng = Double(cols[6].trimmingCharacters(in: .whitespaces)),
                  lat != 0, lng != 0 else { continue }

            let timeStr = cols[0].trimmingCharacters(in: .whitespaces)   // "HHMM" UTC
            let eventDate = combine(day: day, hhmm: timeStr) ?? day

            switch kind {
            case .hail:
                let raw = cols[1].trimmingCharacters(in: .whitespaces)
                let inches: Double? = Int(raw).map { Double($0) / 100.0 } ?? Double(raw)
                guard let inches, inches > 0 else { continue }
                out.append(StormPinEvent(
                    date: eventDate,
                    hailSizeIn: inches,
                    latitude: lat, longitude: lng,
                    source: "NOAA"
                ))
            case .wind:
                let raw = cols[1].trimmingCharacters(in: .whitespaces).uppercased()
                let mph = Int(raw)
                // Accept UNK rows but only at a nominal magnitude so they render.
                let gust = mph ?? (raw == "UNK" ? 55 : nil)
                guard let gust, gust > 0 else { continue }
                out.append(StormPinEvent(
                    date: eventDate,
                    windGustMph: gust,
                    latitude: lat, longitude: lng,
                    source: "NOAA"
                ))
            }
        }
        return out
    }

    private nonisolated static func combine(day: Date, hhmm: String) -> Date? {
        guard hhmm.count == 4, let hh = Int(hhmm.prefix(2)), let mm = Int(hhmm.suffix(2)) else {
            return nil
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = hh; comps.minute = mm
        return cal.date(from: comps)
    }
}

// MARK: - Nominatim DTO

private nonisolated struct NominatimRow: Decodable {
    let display_name: String?
    let lat: String?
    let lon: String?
    let name: String?
    let address: NominatimAddress?

    func toSuggestion() -> AddressSuggestion? {
        guard let lat = lat.flatMap(Double.init),
              let lon = lon.flatMap(Double.init),
              let display = display_name, !display.isEmpty else { return nil }

        // Build a glove-readable two-line layout.
        // Title  : house number + road  (or first display segment)
        // Subtitle: city, state ZIP
        let title: String
        let subtitle: String
        if let a = address {
            let line1 = [a.house_number, a.road].compactMap { $0 }.joined(separator: " ")
            title = line1.isEmpty ? (name ?? display.split(separator: ",").first.map(String.init) ?? display) : line1
            let cityLike = a.city ?? a.town ?? a.village ?? a.hamlet ?? a.suburb ?? ""
            let stateZip = [a.state, a.postcode].compactMap { $0 }.joined(separator: " ")
            let parts = [cityLike, stateZip].filter { !$0.isEmpty }
            subtitle = parts.isEmpty
                ? display.split(separator: ",").dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces)
                : parts.joined(separator: ", ")
        } else {
            let pieces = display.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            title = pieces.first ?? display
            subtitle = pieces.dropFirst().joined(separator: ", ")
        }

        return AddressSuggestion(
            title: title,
            subtitle: subtitle,
            latitude: lat,
            longitude: lon
        )
    }
}

private nonisolated struct NominatimAddress: Decodable {
    let house_number: String?
    let road: String?
    let suburb: String?
    let hamlet: String?
    let village: String?
    let town: String?
    let city: String?
    let state: String?
    let postcode: String?
}

// MARK: - Distance helper

extension StormPinEvent {
    func distanceMiles(from coord: CLLocationCoordinate2D) -> Double {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return here.distance(from: there) / 1609.344
    }
}
