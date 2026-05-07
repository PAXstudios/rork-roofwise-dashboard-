import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

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

// MARK: - Live impl (gated)

#if canImport(WeatherKit)
@available(iOS 16.0, *)
final class LiveWeatherService: WeatherServicing, @unchecked Sendable {
    private let service = WeatherService.shared

    func currentConditions(at coord: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        do {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let weather = try await service.weather(for: location)
            let current = weather.currentWeather
            let tempF = Int(current.temperature.converted(to: .fahrenheit).value.rounded())
            let windMph = Int(current.wind.speed.converted(to: .milesPerHour).value.rounded())
            let hailRisk = Int((current.precipitationIntensity.value * 50).rounded())
            return WeatherSnapshot(
                temperatureF: tempF,
                condition: current.condition.description,
                windMph: windMph,
                hailRiskPct: min(100, max(0, hailRisk)),
                updatedAt: current.date
            )
        } catch {
            throw WeatherServiceError.underlying(error)
        }
    }

    func hourlyForecast(at coord: CLLocationCoordinate2D) async throws -> [WeatherHourlySample] {
        do {
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let weather = try await service.weather(for: location)
            return weather.hourlyForecast.forecast.prefix(24).map { hour in
                WeatherHourlySample(
                    date: hour.date,
                    temperatureF: Int(hour.temperature.converted(to: .fahrenheit).value.rounded()),
                    condition: hour.condition.description,
                    symbolName: hour.symbolName,
                    windMph: Int(hour.wind.speed.converted(to: .milesPerHour).value.rounded()),
                    precipPct: Int((hour.precipitationChance * 100).rounded())
                )
            }
        } catch {
            throw WeatherServiceError.underlying(error)
        }
    }
}
#endif

// MARK: - Factory

enum WeatherServiceFactory {
    static let shared: WeatherServicing = {
        #if canImport(WeatherKit)
        if !APIKeys.USE_MOCKS, #available(iOS 16.0, *) {
            return LiveWeatherService()
        }
        #endif
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
