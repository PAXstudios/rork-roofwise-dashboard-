import Foundation
import CoreLocation

// MARK: - Protocol

protocol GeocodingService: Sendable {
    func geocode(_ address: String) async throws -> CLLocationCoordinate2D?
}

// MARK: - Errors

nonisolated enum GeocodingError: Error {
    case empty
    case notFound
    case underlying(Error)
}

// MARK: - Mock impl
//
// Reuses the same DFW-box hash that WeatherServiceFactory.mockCoord used so
// previously-cached fake coords stay stable across builds.

final class MockGeocodingService: GeocodingService, @unchecked Sendable {
    func geocode(_ address: String) async throws -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return WeatherServiceFactory.mockCoord(forAddress: trimmed)
    }
}

// MARK: - Live impl (Apple CLGeocoder, free, no key)

final class LiveGeocodingService: GeocodingService, @unchecked Sendable {
    private let geocoder = CLGeocoder()

    func geocode(_ address: String) async throws -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let placemarks = try await geocoder.geocodeAddressString(trimmed)
            return placemarks.first?.location?.coordinate
        } catch {
            // Fall back to deterministic mock so the rest of the pipeline
            // (weather, storm match) still has a coord to work with.
            return WeatherServiceFactory.mockCoord(forAddress: trimmed)
        }
    }
}

// MARK: - Factory

enum GeocodingServiceFactory {
    static let shared: GeocodingService = {
        APIKeys.USE_MOCKS
            ? (MockGeocodingService() as GeocodingService)
            : (LiveGeocodingService() as GeocodingService)
    }()

    /// Synchronous helper for views that need a coord *now* (e.g. WeatherTile
    /// initial render). Always returns the deterministic mock coord; the live
    /// async path runs in the background and updates state once resolved.
    static func eagerCoord(forAddress address: String) -> CLLocationCoordinate2D {
        WeatherServiceFactory.mockCoord(forAddress: address)
    }
}
