import Foundation

/// Single source of truth for third-party keys + the global mock toggle.
///
/// Keys are read from `Info.plist` (added per-environment via `INFOPLIST_KEY_*`
/// entries in `project.pbxproj`). Anything missing falls back to a placeholder
/// so the app keeps building. `USE_MOCKS` defaults to `true` until live keys
/// are wired in Phase 4C.
enum APIKeys {
    // MARK: Raw keys
    static let googleMapsApiKey: String      = read("GoogleMapsApiKey")
    static let googleSolarApiKey: String     = read("GoogleSolarApiKey")
    static let googleGeocodingApiKey: String = read("GoogleGeocodingApiKey")
    static let noaaUserAgent: String         = read(
        "NoaaUserAgent",
        default: "RoofWise/1.0 (contact@roofwise.app)"
    )

    /// Global mock-mode flag. Toggled by setting `USE_MOCKS = NO` in Info.plist
    /// (or via an Xcode build setting). Defaults to `true` while live services
    /// are still being wired.
    static let USE_MOCKS: Bool = readBool("USE_MOCKS", default: true)

    // MARK: Live-mode accessors
    static var isLiveGoogleMaps: Bool      { !USE_MOCKS && !googleMapsApiKey.isEmpty }
    static var isLiveGoogleSolar: Bool     { !USE_MOCKS && !googleSolarApiKey.isEmpty }
    static var isLiveGoogleGeocoding: Bool { !USE_MOCKS && !googleGeocodingApiKey.isEmpty }
    static var isLiveNOAA: Bool            { !USE_MOCKS }

    /// Friendly status label for the on-screen pill.
    static var modeLabel: String { USE_MOCKS ? "MOCK" : "LIVE" }

    // MARK: Helpers
    private static func read(_ key: String, default fallback: String = "") -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty else { return fallback }
        return raw
    }

    private static func readBool(_ key: String, default fallback: Bool) -> Bool {
        if let b = Bundle.main.object(forInfoDictionaryKey: key) as? Bool { return b }
        if let s = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            switch s.lowercased() {
            case "no", "false", "0": return false
            case "yes", "true", "1": return true
            default: break
            }
        }
        return fallback
    }
}
