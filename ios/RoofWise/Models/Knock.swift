import Foundation

/// Outcome recorded when a rep finishes a knock during a KnockSession.
/// Distinct from `KnockOutcome` (which powers the legacy KnockedHouse map UI).
nonisolated enum KnockSessionOutcome: String, Codable, CaseIterable, Identifiable {
    case not_home
    case interested
    case not_interested
    case inspection_scheduled
    case follow_up

    nonisolated var id: String { rawValue }

    var label: String {
        switch self {
        case .not_home: return "Not Home"
        case .interested: return "Interested"
        case .not_interested: return "Not Interested"
        case .inspection_scheduled: return "Inspection Scheduled"
        case .follow_up: return "Follow-Up"
        }
    }

    var icon: String {
        switch self {
        case .not_home: return "bell.slash.fill"
        case .interested: return "hand.thumbsup.fill"
        case .not_interested: return "hand.thumbsdown.fill"
        case .inspection_scheduled: return "calendar.badge.checkmark"
        case .follow_up: return "clock.arrow.circlepath"
        }
    }
}

/// A single door knock logged inside a KnockSession.
/// Lat/lng are required (sourced from CLLocationManager at the moment of logging).
/// Address is best-effort reverse-geocoded via GeocodingService.
/// Notes are optional and may be voice-input via SFSpeechRecognizer.
nonisolated struct Knock: Codable, Identifiable {
    let id: UUID
    var lat: Double
    var lng: Double
    var address: String?
    var outcome: KnockSessionOutcome
    var notes: String?
    var follow_up_date: Date?
    /// Lead/inspection id when the knock auto-created a record (e.g. on
    /// `interested` or `inspection_scheduled`). Stored as String for codability
    /// across Lead vs Inspection id types.
    var created_lead_id: String?
    var created_at: Date

    init(
        id: UUID = UUID(),
        lat: Double,
        lng: Double,
        address: String? = nil,
        outcome: KnockSessionOutcome,
        notes: String? = nil,
        follow_up_date: Date? = nil,
        created_lead_id: String? = nil,
        created_at: Date = Date()
    ) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.address = address
        self.outcome = outcome
        self.notes = notes
        self.follow_up_date = follow_up_date
        self.created_lead_id = created_lead_id
        self.created_at = created_at
    }
}
