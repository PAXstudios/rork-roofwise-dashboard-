import Foundation

/// Single source of truth for third-party keys + the global mock toggle.
///
/// Keys are read from `Info.plist` (added per-environment via `INFOPLIST_KEY_*`
/// entries in `project.pbxproj`). Anything missing falls back to a placeholder
/// so the app keeps building. `USE_MOCKS` defaults to `true` until live keys
/// are wired in Phase 4C.
enum APIKeys {
    // MARK: Raw keys
    //
    // Never hardcode live keys here. Each Google key resolves at runtime from the
    // build-time-injected env (`Config.allValues`) first, then an Info.plist entry,
    // then an empty fallback. An empty value flips the matching `isLive*` accessor
    // to false so the UI shows a clean "Not available" state rather than calling an
    // API with a bogus key.
    static var googleMapsApiKey: String      { resolveKey(env: "EXPO_PUBLIC_GOOGLE_MAPS_API_KEY", plist: "GoogleMapsApiKey") }
    static var googleSolarApiKey: String     { resolveKey(env: "EXPO_PUBLIC_GOOGLE_SOLAR_API_KEY", plist: "GoogleSolarApiKey") }
    static var googleGeocodingApiKey: String { resolveKey(env: "EXPO_PUBLIC_GOOGLE_GEOCODING_API_KEY", plist: "GoogleGeocodingApiKey") }
    static var googlePlacesApiKey: String    { resolveKey(env: "EXPO_PUBLIC_GOOGLE_PLACES_API_KEY", plist: "GooglePlacesApiKey") }
    static let noaaUserAgent: String         = read(
        "NoaaUserAgent",
        default: "RoofWise/1.0 (contact@roofwise.app)"
    )
    static let correctionsEndpoint: String   = read(
        "CorrectionsEndpoint",
        default: "https://roofwise.app/v1/corrections/batch"
    )

    // MARK: Supabase
    /// Project URL — read from env at build time via `EXPO_PUBLIC_SUPABASE_URL`,
    /// then an Info.plist `SupabaseUrl` entry. No literal committed to source.
    static var supabaseURL: String {
        let envVal = Config.allValues["EXPO_PUBLIC_SUPABASE_URL"] ?? ""
        return envVal.isEmpty ? read("SupabaseUrl", default: "") : envVal
    }
    /// Publishable / anon key — env (`EXPO_PUBLIC_SUPABASE_ANON_KEY`) then an
    /// Info.plist `SupabaseAnonKey` entry. Anon keys are public-tier but are still
    /// kept out of source control; inject them at build time.
    static var supabaseAnonKey: String {
        let envVal = Config.allValues["EXPO_PUBLIC_SUPABASE_ANON_KEY"] ?? ""
        return envVal.isEmpty ? read("SupabaseAnonKey", default: "") : envVal
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

    // MARK: Phase 2 — AI accuracy flags (all additive; OFF path is unchanged)
    /// Run a blur + brightness check before sending a captured photo to Gemini;
    /// prompt for a recapture when the frame is too poor to analyze reliably.
    static let usePhotoQualityGate: Bool = true
    /// Aggregate + dedupe damage markers across all photos of a slope; boost
    /// confidence for strikes seen in ≥2 frames, drop single-frame outliers.
    static let useMultiPhotoConsensus: Bool = true
    /// Cross-check marker counts against HAAG hits-per-test-square thresholds and
    /// down-weight near-uniform "grid" marker layouts (model hallucination).
    static let useHaagDensityCheck: Bool = true
    /// Use Gemini's shingleScaleEstimate (px/in) to size markers in inches and
    /// drop hail strikes outside the 0.25"–2" physical range.
    static let useScaleAwareSizing: Bool = true
    /// Append the explicit false-positive taxonomy to the Gemini system prompt.
    static let useHardenedPrompt: Bool = true

    // MARK: Live-mode accessors
    static var isLiveGoogleMaps: Bool      { !USE_MOCKS && !googleMapsApiKey.isEmpty }
    static var isLiveGoogleSolar: Bool     { !USE_MOCKS && !googleSolarApiKey.isEmpty }
    static var isLiveGoogleGeocoding: Bool { !USE_MOCKS && !googleGeocodingApiKey.isEmpty }
    static var isLiveGooglePlaces: Bool    { !USE_MOCKS && !googlePlacesApiKey.isEmpty }
    static var isLiveNOAA: Bool            { !USE_MOCKS }

    /// Friendly status label for the on-screen pill.
    static var modeLabel: String { USE_MOCKS ? "MOCK" : "LIVE" }

    // MARK: Helpers
    /// Resolve a key from the build-time env first, then Info.plist, then "".
    private static func resolveKey(env: String, plist: String) -> String {
        if let v = Config.allValues[env], !v.isEmpty { return v }
        return read(plist, default: "")
    }

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
