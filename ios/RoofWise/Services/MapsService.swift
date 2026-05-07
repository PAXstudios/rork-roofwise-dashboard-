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
    static func make() -> MapsService {
        APIKeys.isLiveGoogleMaps ? LiveMapsService() : MockMapsService()
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

// MARK: - Live implementation (Phase 4C will fill these in)

final class LiveMapsService: MapsService {
    let isLive = true

    func suggestAddresses(query: String) async -> [AddressSuggestion] {
        // TODO Phase 4C: Google Places Autocomplete via APIKeys.googleGeocodingApiKey
        []
    }

    func recentStorms() async -> [StormPinEvent] {
        // TODO Phase 4C: NOAA Storm Events with APIKeys.noaaUserAgent
        []
    }
}

// MARK: - Distance helper

extension StormPinEvent {
    func distanceMiles(from coord: CLLocationCoordinate2D) -> Double {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return here.distance(from: there) / 1609.344
    }
}
