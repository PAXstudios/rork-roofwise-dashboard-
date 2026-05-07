import Foundation

struct KnockSession: Codable, Identifiable {
    let id: UUID
    var started_at: Date
    var ended_at: Date?
    /// StormAlert.id (UUID string) if launched from a storm CTA.
    var route_storm_alert_id: String?
    var knocks: [Knock]

    init(
        id: UUID = UUID(),
        started_at: Date = Date(),
        ended_at: Date? = nil,
        route_storm_alert_id: String? = nil,
        knocks: [Knock] = []
    ) {
        self.id = id
        self.started_at = started_at
        self.ended_at = ended_at
        self.route_storm_alert_id = route_storm_alert_id
        self.knocks = knocks
    }

    var isActive: Bool { ended_at == nil }
    var knockCount: Int { knocks.count }
}
