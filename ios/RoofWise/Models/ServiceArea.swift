import Foundation

nonisolated struct ServiceArea: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case zip, cityState }

    let id: UUID
    var label: String
    var kind: Kind
    var zip: String?
    var city: String?
    var state: String?
    var centerLat: Double?
    var centerLng: Double?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        kind: Kind,
        zip: String? = nil,
        city: String? = nil,
        state: String? = nil,
        centerLat: Double? = nil,
        centerLng: Double? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.zip = zip
        self.city = city
        self.state = state
        self.centerLat = centerLat
        self.centerLng = centerLng
        self.addedAt = addedAt
    }

    /// Parses a free-text input into a ServiceArea draft (without geocoded
    /// coords). Accepts:
    ///   - 5-digit ZIP        → .zip
    ///   - "City ST"          → .cityState
    ///   - "City, ST"         → .cityState
    /// Returns nil for unrecognized formats.
    static func parse(_ raw: String) -> ServiceArea? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // ZIP
        let digits = trimmed.filter { $0.isNumber }
        if digits.count == 5, digits == trimmed {
            return ServiceArea(label: digits, kind: .zip, zip: digits)
        }

        // City ST  or  City, ST
        let cleaned = trimmed.replacingOccurrences(of: ",", with: " ")
        let parts = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        let stateToken = parts.last ?? ""
        guard stateToken.count == 2, stateToken.allSatisfy({ $0.isLetter }) else { return nil }
        let cityTokens = parts.dropLast()
        guard !cityTokens.isEmpty else { return nil }
        let city = cityTokens.joined(separator: " ")
        let state = stateToken.uppercased()
        let cityTitle = city
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return ServiceArea(
            label: "\(cityTitle) \(state)",
            kind: .cityState,
            city: cityTitle,
            state: state
        )
    }
}
