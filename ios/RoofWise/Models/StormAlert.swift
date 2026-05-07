import Foundation

nonisolated struct StormAlert: Codable, Identifiable, Hashable, Sendable {
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

    init(
        id: UUID = UUID(),
        areaId: UUID,
        areaLabel: String,
        event: NoaaStormEvent,
        distanceMi: Double,
        createdAt: Date = .now,
        isRead: Bool = false
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
}
