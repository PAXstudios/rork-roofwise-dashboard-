import SwiftUI
import CoreLocation

enum KnockOutcome: String, CaseIterable, Identifiable, Codable {
    case notKnocked = "Not Knocked"
    case noAnswer = "No Answer"
    case interested = "Interested"
    case notInterested = "Not Interested"
    case scheduled = "Scheduled"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .notKnocked: return Theme.inkFaint
        case .noAnswer: return Theme.amber
        case .interested: return Theme.mint
        case .notInterested: return Theme.crimson
        case .scheduled: return Color(red: 0.98, green: 0.55, blue: 0.18) // orange
        }
    }

    var icon: String {
        switch self {
        case .notKnocked: return "house"
        case .noAnswer: return "bell.slash.fill"
        case .interested: return "hand.thumbsup.fill"
        case .notInterested: return "hand.thumbsdown.fill"
        case .scheduled: return "calendar.badge.clock"
        }
    }

    var shortLabel: String {
        switch self {
        case .notKnocked: return "Not Knocked"
        case .noAnswer: return "No Answer"
        case .interested: return "Interested"
        case .notInterested: return "Not Int."
        case .scheduled: return "Scheduled"
        }
    }
}

struct KnockedHouse: Identifiable {
    let id: UUID = UUID()
    /// Normalized 0..1 coordinates inside the map view.
    var x: CGFloat
    var y: CGFloat
    /// Optional GPS stamp (filled if location available).
    var latitude: Double?
    var longitude: Double?
    var outcome: KnockOutcome
    var notes: String = ""
    var loggedAt: Date = Date()
    /// The rep who logged the knock.
    var rep: String = "Sarah Jenkins"

    var prettyCoord: String {
        guard let lat = latitude, let lng = longitude else { return "GPS pending" }
        return String(format: "%.4f, %.4f", lat, lng)
    }
}
