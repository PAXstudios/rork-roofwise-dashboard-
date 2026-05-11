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
            // No silent fallback — caller decides how to handle a miss.
            print("[GeocodingService] CLGeocoder failed for \"\(trimmed)\": \(error)")
            return nil
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

    /// Synchronous helper for legacy views that need a coord *now* before the
    /// async geocode resolves. Returns a deterministic deviceless coord as a
    /// placeholder anchor; callers should replace with the real CLGeocoder
    /// result as soon as it arrives. Not a Live geocode.
    static func eagerCoord(forAddress address: String) -> CLLocationCoordinate2D {
        WeatherServiceFactory.mockCoord(forAddress: address)
    }
}
