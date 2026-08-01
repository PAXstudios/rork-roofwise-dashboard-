import SwiftUI
import Foundation
import CoreLocation

/// Resolves real storm history near a property from cached `StormAlertStore`
/// alerts (and optionally NOAA via `fetchHits`). Never invents storms — returns
/// empty when nothing has been observed near the property yet.
enum PropertyStormService {

    struct PropertyHit: Identifiable {
        let id = UUID()
        let storm: StormEvent
        /// 0 - 1, how directly this property sits inside the impact core
        let coverage: Double
        /// "Direct hit", "Edge of core", "Glancing"
        var coverageLabel: String {
            switch coverage {
            case 0.75...: return "Direct hit"
            case 0.5..<0.75: return "Inside impact zone"
            case 0.25..<0.5: return "Edge of core"
            default: return "Glancing"
            }
        }
        var coverageColor: Color {
            switch coverage {
            case 0.75...: return Theme.crimson
            case 0.5..<0.75: return Theme.ember
            case 0.25..<0.5: return Theme.amber
            default: return Theme.inkFaint
            }
        }
    }

    /// Synchronous snapshot from already-cached alerts near the customer.
    static func hits(for customer: Customer) -> [PropertyHit] {
        guard let coord = customer.coordinate else { return [] }
        let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return StormAlertStore.shared.alerts
            .map { alert -> (StormAlert, Double) in
                let d = origin.distance(from: CLLocation(latitude: alert.latitude,
                                                         longitude: alert.longitude)) / 1609.34
                return (alert, d)
            }
            .filter { $0.1 <= 25 }
            .sorted { $0.1 < $1.1 }
            .prefix(6)
            .map { pair in
                let coverage = max(0.1, min(1.0, 1.0 - (pair.1 / 25.0)))
                return PropertyHit(storm: makeStormEvent(from: pair.0), coverage: coverage)
            }
    }

    static func mostRecentSevereHit(for customer: Customer) -> PropertyHit? {
        hits(for: customer).first {
            ($0.storm.sizeInches ?? 0) >= 1.0 ||
            ($0.storm.windMPH ?? 0) >= 58 ||
            $0.coverage >= 0.6 ||
            $0.storm.band == .severe
        }
    }

    /// Async fetch of NOAA history within 25 mi of the property (last 3 years).
    static func fetchHits(for customer: Customer) async -> [PropertyHit] {
        guard let coord = customer.coordinate else { return hits(for: customer) }
        do {
            let events = try await StormEventsServiceFactory.shared.events(
                near: coord,
                radiusMi: 25,
                sinceMonthsBack: 37
            )
            let origin = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            return events.prefix(8).map { e in
                let d = origin.distance(from: CLLocation(latitude: e.latitude,
                                                         longitude: e.longitude)) / 1609.34
                let coverage = max(0.1, min(1.0, 1.0 - (d / 25.0)))
                return PropertyHit(storm: makeStormEvent(from: e), coverage: coverage)
            }
        } catch {
            return hits(for: customer)
        }
    }

    // MARK: - Bridges

    private static func makeStormEvent(from alert: StormAlert) -> StormEvent {
        let type: StormType = alert.eventType == .wind || alert.eventType == .tornado ? .wind : .hail
        let year = Calendar.current.component(.year, from: alert.eventDate)
        let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
        let intensity: Double = {
            if let h = alert.magnitudeIn { return min(1, h / 2.5) }
            if let w = alert.windMph { return min(1, Double(w) / 100) }
            return 0.4
        }()
        return StormEvent(
            type: type,
            year: year,
            date: df.string(from: alert.eventDate),
            intensity: intensity,
            sizeInches: alert.magnitudeIn,
            windMPH: alert.windMph,
            x: 0.5, y: 0.5, radius: 0.2,
            propertiesAffected: alert.propertyCount
        )
    }

    private static func makeStormEvent(from e: NoaaStormEvent) -> StormEvent {
        let type: StormType = e.eventType == .wind || e.eventType == .tornado ? .wind : .hail
        let year = Calendar.current.component(.year, from: e.eventDate)
        let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
        let intensity: Double = {
            if let h = e.magnitudeIn { return min(1, h / 2.5) }
            if let w = e.windMph { return min(1, Double(w) / 100) }
            return 0.4
        }()
        return StormEvent(
            type: type,
            year: year,
            date: df.string(from: e.eventDate),
            intensity: intensity,
            sizeInches: e.magnitudeIn,
            windMPH: e.windMph,
            x: 0.5, y: 0.5, radius: 0.2,
            propertiesAffected: 0
        )
    }
}
