import Foundation
import CoreLocation

// MARK: - Snapshot

nonisolated struct WeatherSnapshot: Hashable, Sendable {
    var temperatureF: Int
    var condition: String
    var windMph: Int
    var hailRiskPct: Int
    var updatedAt: Date

    static let placeholder = WeatherSnapshot(
        temperatureF: 72,
        condition: "Partly Cloudy",
        windMph: 8,
        hailRiskPct: 12,
        updatedAt: .now
    )
}

nonisolated struct WeatherHourlySample: Hashable, Sendable, Identifiable {
    let id = UUID()
    var date: Date
    var temperatureF: Int
    var condition: String
    var symbolName: String
    var windMph: Int
    var precipPct: Int
}

// MARK: - Errors

nonisolated enum WeatherServiceError: Error {
    case unavailable
    case underlying(Error)
}

// MARK: - Protocol

protocol WeatherServicing: Sendable {
    func currentConditions(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot
    func hourlyForecast(at coord: CLLocationCoordinate2D) async throws -> [WeatherHourlySample]
}

// MARK: - Mock impl

final class MockWeatherService: WeatherServicing, @unchecked Sendable {
    func currentConditions(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        try? await Task.sleep(for: .milliseconds(120))
        return Self.snapshot(for: coord, at: .now)
    }

    func hourlyForecast(at coord: CLLocationCoordinate2D) async throws -> [WeatherHourlySample] {
        try? await Task.sleep(for: .milliseconds(120))
        let base = Self.snapshot(for: coord, at: .now)
        let symbols = ["sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.drizzle.fill",
                       "cloud.rain.fill", "cloud.bolt.fill"]
        let now = Calendar.current.date(bySetting: .minute, value: 0, of: .now) ?? .now
        return (0..<24).map { i in
            let drift = Int(sin(Double(i) / 3.0) * 6)
            let temp = base.temperatureF + drift
            let symIndex = (Self.coordHash(coord) + i) % symbols.count
            let cond = ["Sunny", "Partly Cloudy", "Cloudy", "Drizzle", "Rain", "Storms"][symIndex]
            return WeatherHourlySample(
                date: now.addingTimeInterval(Double(i) * 3600),
                temperatureF: temp,
                condition: cond,
                symbolName: symbols[symIndex],
                windMph: max(1, base.windMph + (i % 5) - 2),
                precipPct: min(95, max(0, base.hailRiskPct + (i % 7) * 3 - 4))
            )
        }
    }

    static func snapshot(for coord: CLLocationCoordinate2D, at date: Date) -> WeatherSnapshot {
        let h = coordHash(coord)
        let conditions = ["Sunny", "Partly Cloudy", "Cloudy", "Light Rain",
                          "Thunderstorms", "Windy", "Hazy"]
        return WeatherSnapshot(
            temperatureF: 64 + (h % 28),
            condition: conditions[h % conditions.count],
            windMph: 4 + (h % 18),
            hailRiskPct: (h * 7) % 100,
            updatedAt: date
        )
    }

    static func coordHash(_ coord: CLLocationCoordinate2D) -> Int {
        let lat = Int((coord.latitude * 1000).rounded())
        let lon = Int((coord.longitude * 1000).rounded())
        return abs(lat &* 31 &+ lon)
    }
}

// MARK: - Google Weather provider (primary live impl)

/// Live weather via Google Weather API (weather.googleapis.com).
/// Uses the same unrestricted Google Cloud key as Maps/Solar/Geocoding.
/// Requires the "Weather API" to be enabled in the Cloud Console.
final class GoogleWeatherProvider: WeatherServicing, @unchecked Sendable {
    private let apiKey: String

    init(apiKey: String = APIKeys.googleMapsApiKey) {
        self.apiKey = apiKey
    }

    private struct CurrentDTO: Decodable {
        struct Temp: Decodable { let degrees: Double?; let unit: String? }
        struct CondDesc: Decodable { let text: String? }
        struct Cond: Decodable { let description: CondDesc?; let type: String? }
        struct WindSpeed: Decodable { let value: Double?; let unit: String? }
        struct Wind: Decodable { let speed: WindSpeed? }
        struct PrecipProb: Decodable { let percent: Int?; let type: String? }
        struct Precip: Decodable { let probability: PrecipProb? }
        let currentTime: String?
        let temperature: Temp?
        let weatherCondition: Cond?
        let wind: Wind?
        let precipitation: Precip?
        let thunderstormProbability: Int?
    }

    private struct HourlyDTO: Decodable {
        struct Interval: Decodable { let startTime: String? }
        struct Temp: Decodable { let degrees: Double?; let unit: String? }
        struct CondDesc: Decodable { let text: String? }
        struct Cond: Decodable { let description: CondDesc?; let type: String? }
        struct WindSpeed: Decodable { let value: Double?; let unit: String? }
        struct Wind: Decodable { let speed: WindSpeed? }
        struct PrecipProb: Decodable { let percent: Int? }
        struct Precip: Decodable { let probability: PrecipProb? }
        let interval: Interval?
        let temperature: Temp?
        let weatherCondition: Cond?
        let wind: Wind?
        let precipitation: Precip?
    }

    private struct HourlyResponse: Decodable {
        let forecastHours: [HourlyDTO]?
    }

    func currentConditions(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        print("[WeatherService] Google Weather request → \(coord)")
        var components = URLComponents(string: "https://weather.googleapis.com/v1/currentConditions:lookup")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location.latitude", value: String(coord.latitude)),
            URLQueryItem(name: "location.longitude", value: String(coord.longitude)),
            URLQueryItem(name: "unitsSystem", value: "IMPERIAL"),
        ]
        guard let url = components.url else { throw WeatherServiceError.unavailable }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            print("[WeatherService] Google Weather error: \(http.statusCode) \(bodyString.prefix(500))")
            if http.statusCode == 403 {
                print("[WeatherService] 403 — enable the Weather API for this key in Google Cloud Console.")
            }
            throw WeatherServiceError.unavailable
        }

        let dto: CurrentDTO
        do {
            dto = try JSONDecoder().decode(CurrentDTO.self, from: data)
        } catch {
            print("[WeatherService] Google Weather decode error: \(error)")
            throw WeatherServiceError.underlying(error)
        }

        let temp = Self.toFahrenheit(dto.temperature?.degrees, unit: dto.temperature?.unit)
        let condition = dto.weatherCondition?.description?.text
            ?? Self.prettifyConditionType(dto.weatherCondition?.type)
            ?? "—"
        let windMph = Self.toMph(dto.wind?.speed?.value, unit: dto.wind?.speed?.unit)
        let hailRisk = max(
            dto.thunderstormProbability ?? 0,
            dto.precipitation?.probability?.percent ?? 0
        )
        let updated = Self.parseDate(dto.currentTime) ?? .now

        print("[WeatherService] Google Weather response: \(temp)°F, \(condition)")

        return WeatherSnapshot(
            temperatureF: temp,
            condition: condition,
            windMph: windMph,
            hailRiskPct: min(100, max(0, hailRisk)),
            updatedAt: updated
        )
    }

    func hourlyForecast(at coord: CLLocationCoordinate2D) async throws -> [WeatherHourlySample] {
        print("[WeatherService] Google Weather request → \(coord)")
        var components = URLComponents(string: "https://weather.googleapis.com/v1/forecast/hours:lookup")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location.latitude", value: String(coord.latitude)),
            URLQueryItem(name: "location.longitude", value: String(coord.longitude)),
            URLQueryItem(name: "hours", value: "24"),
            URLQueryItem(name: "unitsSystem", value: "IMPERIAL"),
        ]
        guard let url = components.url else { throw WeatherServiceError.unavailable }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            print("[WeatherService] Google Weather error: \(http.statusCode) \(bodyString.prefix(500))")
            if http.statusCode == 403 {
                print("[WeatherService] 403 — enable the Weather API for this key in Google Cloud Console.")
            }
            throw WeatherServiceError.unavailable
        }

        let resp: HourlyResponse
        do {
            resp = try JSONDecoder().decode(HourlyResponse.self, from: data)
        } catch {
            print("[WeatherService] Google Weather decode error: \(error)")
            throw WeatherServiceError.underlying(error)
        }

        let hours = resp.forecastHours ?? []
        return hours.prefix(24).map { h in
            let date = Self.parseDate(h.interval?.startTime) ?? .now
            let temp = Self.toFahrenheit(h.temperature?.degrees, unit: h.temperature?.unit)
            let condText = h.weatherCondition?.description?.text
                ?? Self.prettifyConditionType(h.weatherCondition?.type)
                ?? "—"
            let symbol = Self.sfSymbol(for: h.weatherCondition?.type)
            let wind = Self.toMph(h.wind?.speed?.value, unit: h.wind?.speed?.unit)
            let precip = h.precipitation?.probability?.percent ?? 0
            return WeatherHourlySample(
                date: date,
                temperatureF: temp,
                condition: condText,
                symbolName: symbol,
                windMph: wind,
                precipPct: min(100, max(0, precip))
            )
        }
    }

    // MARK: - Helpers
    private static func toFahrenheit(_ value: Double?, unit: String?) -> Int {
        guard let v = value else { return 0 }
        let u = (unit ?? "").uppercased()
        if u.contains("FAHRENHEIT") || u == "F" { return Int(v.rounded()) }
        // Default to celsius if unspecified.
        return Int(((v * 9.0 / 5.0) + 32.0).rounded())
    }

    private static func toMph(_ value: Double?, unit: String?) -> Int {
        guard let v = value else { return 0 }
        let u = (unit ?? "").uppercased()
        if u.contains("MILES_PER_HOUR") || u == "MPH" { return Int(v.rounded()) }
        if u.contains("KILOMETERS_PER_HOUR") || u == "KPH" || u == "KM/H" {
            return Int((v * 0.621371).rounded())
        }
        // meters per second fallback
        if u.contains("METERS_PER_SECOND") || u == "M/S" {
            return Int((v * 2.23694).rounded())
        }
        return Int(v.rounded())
    }

    private static func parseDate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    private static func prettifyConditionType(_ type: String?) -> String? {
        guard let t = type, !t.isEmpty else { return nil }
        return t.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func sfSymbol(for type: String?) -> String {
        switch (type ?? "").uppercased() {
        case let s where s.contains("THUNDER"): return "cloud.bolt.fill"
        case let s where s.contains("RAIN") && s.contains("HEAVY"): return "cloud.heavyrain.fill"
        case let s where s.contains("RAIN"): return "cloud.rain.fill"
        case let s where s.contains("DRIZZLE"): return "cloud.drizzle.fill"
        case let s where s.contains("SNOW"): return "cloud.snow.fill"
        case let s where s.contains("HAIL"): return "cloud.hail.fill"
        case let s where s.contains("FOG") || s.contains("HAZE") || s.contains("MIST"): return "cloud.fog.fill"
        case let s where s.contains("WIND"): return "wind"
        case let s where s.contains("PARTLY_CLOUDY") || s.contains("MOSTLY_CLEAR"): return "cloud.sun.fill"
        case let s where s.contains("CLOUDY") || s.contains("OVERCAST"): return "cloud.fill"
        case let s where s.contains("CLEAR") || s.contains("SUNNY"): return "sun.max.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Factory

enum WeatherServiceFactory {
    static let shared: WeatherServicing = {
        if !APIKeys.USE_MOCKS {
            return GoogleWeatherProvider()
        }
        return MockWeatherService()
    }()

    /// Cheap deterministic "geocode" used until we wire Google Geocoding (Phase 4C).
    /// Hashes the address string into a coord roughly inside the DFW metro so the
    /// mocked weather still feels regional.
    static func mockCoord(forAddress address: String) -> CLLocationCoordinate2D {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .planoTX }
        let h = abs(trimmed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let latJitter = Double(h % 200) / 1000.0    // 0...0.2
        let lonJitter = Double((h / 200) % 200) / 1000.0
        return CLLocationCoordinate2D(
            latitude: 33.0 + latJitter,
            longitude: -96.8 + lonJitter
        )
    }
}

extension CLLocationCoordinate2D {
    static let planoTX = CLLocationCoordinate2D(latitude: 33.0198, longitude: -96.6989)
}
