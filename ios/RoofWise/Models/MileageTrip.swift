import Foundation
import CoreLocation
import SwiftUI

enum TripPurpose: String, Codable, CaseIterable, Identifiable {
    case doorKnocking = "Door Knocking"
    case inspection = "Inspection"
    case followUp = "Follow-up"
    case jobSite = "Job Site Visit"
    case supplyRun = "Supply Run"
    case estimate = "Estimate"
    case clientMeeting = "Client Meeting"
    case office = "Office"
    case other = "Other"
    case personal = "Personal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .doorKnocking:  return "hand.tap.fill"
        case .inspection:    return "binoculars.fill"
        case .followUp:      return "arrow.uturn.right.circle.fill"
        case .jobSite:       return "hammer.fill"
        case .supplyRun:     return "shippingbox.fill"
        case .estimate:      return "doc.text.fill"
        case .clientMeeting: return "person.2.fill"
        case .office:        return "building.2.fill"
        case .other:         return "ellipsis.circle.fill"
        case .personal:      return "car.fill"
        }
    }

    var tint: Color {
        switch self {
        case .doorKnocking:  return Theme.ember
        case .inspection:    return Theme.ember
        case .followUp:      return Theme.amber
        case .jobSite:       return Theme.crimson
        case .supplyRun:     return Theme.sky
        case .estimate:      return Theme.amber
        case .clientMeeting: return Theme.mint
        case .office:        return Theme.inkSoft
        case .other:         return Theme.inkSoft
        case .personal:      return Theme.inkFaint
        }
    }

    var isDeductible: Bool { self != .personal }
}

struct MileageTripPoint: Codable, Hashable {
    let lat: Double
    let lon: Double
    let timestamp: Date
}

struct MileageTrip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date
    var miles: Double
    var purpose: TripPurpose
    var startLabel: String
    var endLabel: String
    var jobName: String?
    var notes: String?
    var path: [MileageTripPoint]

    var durationSeconds: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var durationString: String {
        let s = Int(durationSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - IRS rate (2026 estimate; configurable in UI)

enum MileageRates {
    /// IRS standard business mileage rate.
    static let standardBusinessPerMile: Double = 0.67
}

extension MileageTrip {
    func reimbursement(rate: Double = MileageRates.standardBusinessPerMile) -> Double {
        guard purpose.isDeductible else { return 0 }
        return miles * rate
    }
}

// MARK: - Persistence

@MainActor
@Observable
final class MileageStore {
    static let shared = MileageStore()

    private let key = "rw.mileage.trips.v1"
    private let rateKey = "rw.mileage.rate.v1"
    private let trackingEnabledKey = "rw.mileage.trackingEnabled.v1"

    var trips: [MileageTrip] = []
    var ratePerMile: Double = MileageRates.standardBusinessPerMile
    var trackingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(trackingEnabled, forKey: trackingEnabledKey)
        }
    }

    private init() {
        load()
    }

    func add(_ trip: MileageTrip) {
        trips.insert(trip, at: 0)
        persist()
    }

    func delete(_ trip: MileageTrip) {
        trips.removeAll { $0.id == trip.id }
        persist()
    }

    func update(_ trip: MileageTrip) {
        guard let idx = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[idx] = trip
        persist()
    }

    func setRate(_ rate: Double) {
        ratePerMile = max(0, rate)
        UserDefaults.standard.set(ratePerMile, forKey: rateKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(trips) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([MileageTrip].self, from: data) {
            trips = decoded
        } else {
            trips = MileageStore.seedTrips()
        }
        let r = UserDefaults.standard.double(forKey: rateKey)
        if r > 0 { ratePerMile = r }
        if UserDefaults.standard.object(forKey: trackingEnabledKey) != nil {
            trackingEnabled = UserDefaults.standard.bool(forKey: trackingEnabledKey)
        }
    }

    // MARK: Aggregations

    func trips(in interval: DateInterval) -> [MileageTrip] {
        trips.filter { interval.contains($0.startedAt) }
    }

    var weekToDate: [MileageTrip] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return trips.filter { $0.startedAt >= start }
    }

    var monthToDate: [MileageTrip] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .month, for: Date())?.start else { return [] }
        return trips.filter { $0.startedAt >= start }
    }

    var yearToDate: [MileageTrip] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .year, for: Date())?.start else { return [] }
        return trips.filter { $0.startedAt >= start }
    }

    func totalMiles(_ trips: [MileageTrip]) -> Double {
        trips.reduce(0) { $0 + $1.miles }
    }

    func totalReimbursement(_ trips: [MileageTrip]) -> Double {
        trips.reduce(0) { $0 + $1.reimbursement(rate: ratePerMile) }
    }

    // MARK: Demo seed

    private static func seedTrips() -> [MileageTrip] {
        let now = Date()
        func days(_ d: Int, _ h: Int = 9) -> Date {
            Calendar.current.date(byAdding: .hour, value: -d * 24 + h, to: now) ?? now
        }
        return [
            MileageTrip(startedAt: days(0, -2), endedAt: days(0, -1),
                        miles: 14.6, purpose: .inspection,
                        startLabel: "Office — 4th & Main",
                        endLabel: "Briarwood Heights",
                        jobName: "Hendricks · Hail Inspection",
                        notes: "Post-storm pass-through", path: []),
            MileageTrip(startedAt: days(1, -3), endedAt: days(1, -2),
                        miles: 22.8, purpose: .estimate,
                        startLabel: "Briarwood Heights",
                        endLabel: "Cedar Ridge Estates",
                        jobName: "Tanaka · Roof Estimate",
                        notes: nil, path: []),
            MileageTrip(startedAt: days(2, -5), endedAt: days(2, -4),
                        miles: 8.1, purpose: .supplyRun,
                        startLabel: "ABC Supply",
                        endLabel: "Job Site — Oak Park",
                        jobName: "Patel · Re-roof",
                        notes: "Drip edge + ice/water shield", path: []),
            MileageTrip(startedAt: days(4, -2), endedAt: days(4, -1),
                        miles: 31.4, purpose: .jobSite,
                        startLabel: "Office — 4th & Main",
                        endLabel: "Lakeview Estates",
                        jobName: "Reynolds · Tear-off",
                        notes: nil, path: []),
            MileageTrip(startedAt: days(7, -4), endedAt: days(7, -3),
                        miles: 11.0, purpose: .clientMeeting,
                        startLabel: "Office — 4th & Main",
                        endLabel: "Adjuster Office",
                        jobName: "State Farm · Adjuster Meet",
                        notes: "Met with Carla R.", path: [])
        ]
    }
}
