import Foundation

/// Single source of truth for third-party keys + the global mock toggle.
///
/// Keys are read from `Info.plist` (added per-environment via `INFOPLIST_KEY_*`
/// entries in `project.pbxproj`). Anything missing falls back to a placeholder
/// so the app keeps building. `USE_MOCKS` defaults to `true` until live keys
/// are wired in Phase 4C.
enum APIKeys {
    // MARK: Raw keys
    static let googleMapsApiKey: String      = "AIzaSyDmnzp1Q23igS3XTPA6BMcIGOygkmyYSBM"
    static let googleSolarApiKey: String     = "AIzaSyDmnzp1Q23igS3XTPA6BMcIGOygkmyYSBM"
    static let googleGeocodingApiKey: String = "AIzaSyDmnzp1Q23igS3XTPA6BMcIGOygkmyYSBM"
    static let googlePlacesApiKey: String    = "AIzaSyDmnzp1Q23igS3XTPA6BMcIGOygkmyYSBM"
    static let noaaUserAgent: String         = read(
        "NoaaUserAgent",
        default: "RoofWise/1.0 (contact@roofwise.app)"
    )
    static let correctionsEndpoint: String   = read(
        "CorrectionsEndpoint",
        default: "https://roofwise.app/v1/corrections/batch"
    )

    // MARK: Supabase
    /// Project URL — public, safe to ship. Read from env at build time via
    /// `Config.EXPO_PUBLIC_SUPABASE_URL`; falls back to the literal so the app
    /// keeps building if env injection isn't wired.
    static var supabaseURL: String {
        let envVal = Config.allValues["EXPO_PUBLIC_SUPABASE_URL"] ?? ""
        return envVal.isEmpty ? "https://mzsabjegtxmzlfpxmmfm.supabase.co" : envVal
    }
    /// Publishable / anon key — safe for client.
    /// Fallback is the JWT anon key for project `mzsabjegtxmzlfpxmmfm`, used
    /// when env injection isn't wired (e.g. Config.swift hasn't regenerated
    /// to include `EXPO_PUBLIC_SUPABASE_ANON_KEY` yet).
    static var supabaseAnonKey: String {
        let envVal = Config.allValues["EXPO_PUBLIC_SUPABASE_ANON_KEY"] ?? ""
        return envVal.isEmpty ? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im16c2FiamVndHhtemxmcHhtbWZtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzMDQyNzIsImV4cCI6MjA5NDg4MDI3Mn0.llzXp4wYKeR1DjBTah7YzVQEaQALla3UI5TmvU2QGJc" : envVal
    }
    static var isLiveSupabase: Bool { !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty }

    /// Global mock-mode flag. Toggled by setting `USE_MOCKS = NO` in Info.plist
    /// (or via an Xcode build setting). Defaults to `true` while live services
    /// are still being wired.
    static let USE_MOCKS: Bool = false

    /// Phase 8 feature flag. When `true`, the analyze pipeline surfaces
    /// structured per-category Gemini confidence to the UI (slope chips,
    /// verify-with-inspector badges) and the training queue switches from the
    /// deterministic stub to real `confidence_avg < 0.6` enqueue. Default `false`
    /// — flip to `true` to enable. Strictly additive; everything below is OFF
    /// until you flip this.
    static let useStructuredConfidence: Bool = true

    static let requireAuth: Bool = false // dev bypass; set to true to enforce sign-in

    // MARK: Live-mode accessors
    static var isLiveGoogleMaps: Bool      { !USE_MOCKS && !googleMapsApiKey.isEmpty }
    static var isLiveGoogleSolar: Bool     { !USE_MOCKS && !googleSolarApiKey.isEmpty }
    static var isLiveGoogleGeocoding: Bool { !USE_MOCKS && !googleGeocodingApiKey.isEmpty }
    static var isLiveGooglePlaces: Bool    { !USE_MOCKS && !googlePlacesApiKey.isEmpty }
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
