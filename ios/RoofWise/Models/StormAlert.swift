import Foundation

nonisolated struct StormAlert: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case new
        case dismissed
        case actedOn = "acted_on"
        case snoozed
    }

    let id: UUID
    let areaId: UUID
    let areaLabel: String
    let eventId: String
    let eventDate: Date
    let eventType: StormEventType
    let magnitudeIn: Double?
    let windMph: Int?
    let latitude: Double
    let longitude: Double
    let distanceMi: Double
    let source: String
    let createdAt: Date
    var isRead: Bool
    var status: Status
    var snoozedUntil: Date?
    var propertyCount: Int

    init(
        id: UUID = UUID(),
        areaId: UUID,
        areaLabel: String,
        event: NoaaStormEvent,
        distanceMi: Double,
        propertyCount: Int = 1,
        createdAt: Date = .now,
        isRead: Bool = false,
        status: Status = .new,
        snoozedUntil: Date? = nil
    ) {
        self.id = id
        self.areaId = areaId
        self.areaLabel = areaLabel
        self.eventId = event.id
        self.eventDate = event.eventDate
        self.eventType = event.eventType
        self.magnitudeIn = event.magnitudeIn
        self.windMph = event.windMph
        self.latitude = event.latitude
        self.longitude = event.longitude
        self.distanceMi = distanceMi
        self.source = event.source
        self.createdAt = createdAt
        self.isRead = isRead
        self.status = status
        self.snoozedUntil = snoozedUntil
        self.propertyCount = propertyCount
    }

    // MARK: Codable (backwards-compatible)

    private enum CodingKeys: String, CodingKey {
        case id, areaId, areaLabel, eventId, eventDate, eventType,
             magnitudeIn, windMph, latitude, longitude, distanceMi,
             source, createdAt, isRead, status, snoozedUntil, propertyCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        areaId = try c.decode(UUID.self, forKey: .areaId)
        areaLabel = try c.decode(String.self, forKey: .areaLabel)
        eventId = try c.decode(String.self, forKey: .eventId)
        eventDate = try c.decode(Date.self, forKey: .eventDate)
        eventType = try c.decode(StormEventType.self, forKey: .eventType)
        magnitudeIn = try c.decodeIfPresent(Double.self, forKey: .magnitudeIn)
        windMph = try c.decodeIfPresent(Int.self, forKey: .windMph)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        distanceMi = try c.decode(Double.self, forKey: .distanceMi)
        source = try c.decode(String.self, forKey: .source)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .new
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        propertyCount = try c.decodeIfPresent(Int.self, forKey: .propertyCount) ?? 1
    }

    /// True when the alert is currently considered active (visible) — i.e. not
    /// dismissed/acted-on, and not currently inside a snooze window.
    var isActive: Bool {
        switch status {
        case .new: return true
        case .dismissed, .actedOn: return false
        case .snoozed:
            if let until = snoozedUntil { return until <= Date() }
            return true
        }
    }

    /// Short headline e.g. "1.75″ hail near Plano TX 75024".
    var headline: String {
        switch eventType {
        case .hail:
            let size = magnitudeIn.map { String(format: "%.2f″", $0) } ?? "Hail"
            return "\(size) hail near \(areaLabel)"
        case .wind:
            let mph = windMph.map { "\($0) mph" } ?? "High"
            return "\(mph) wind near \(areaLabel)"
        case .tornado:
            return "Tornado near \(areaLabel)"
        }
    }

    var magnitudeValue: Double {
        switch eventType {
        case .hail: return magnitudeIn ?? 0
        case .wind, .tornado: return Double(windMph ?? 0)
        }
    }

    var magnitudeUnit: String {
        switch eventType {
        case .hail: return "in"
        case .wind, .tornado: return "mph"
        }
    }

    /// Bridge to the on-map pin model. Used by MapHubView's `focusedStorm`
    /// param so push/hero taps can drop the user into the impacted area.
    var asPinEvent: StormPinEvent {
        StormPinEvent(
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
