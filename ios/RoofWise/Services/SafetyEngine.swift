import Foundation

// MARK: - RoofWise Safety Engine (Stage 7)
//
// Deterministic roof-walk go/no-go assessment. Pure inputs in, rating + reasons
// out — no networking, no side effects. `SafetyRating` is shared with the
// RoofWise Decision Engine (defined in RoofWiseDecisionEngineService.swift).
//
// Thresholds cross-reference HAAG inspection guidance and OSHA fall-safety.

nonisolated enum SurfaceDryness: String, Codable, Sendable {
    case dry, damp, wet, icy, unknown
}

nonisolated struct SafetyInputs: Codable, Sendable, Hashable {
    let windGustMph: Double?
    let sustainedWindMph: Double?
    let precipChance01: Double?            // 0.0–1.0
    let lightningProbability01: Double?    // 0.0–1.0
    let temperatureF: Double?
    let pitchRatio: Double?                // e.g. 6/12 = 0.5
    let surfaceDryness: SurfaceDryness?
}

nonisolated struct SafetyAssessment: Codable, Sendable, Hashable {
    let rating: SafetyRating
    let reasons: [String]
    let computedAt: Date
    let inputs: SafetyInputs
}

nonisolated enum SafetyEngine {
    /// Pure function. Inputs in, rating + reasons out.
    ///
    /// UNSAFE if any: gust > 25 mph, sustained > 20 mph, lightning prob > 0.30,
    ///   precip > 0.50, temp < 32°F, pitch > 0.83 (10/12), surface wet/icy.
    /// USE_CAUTION if any: gust 15…25, sustained 10…20, lightning 0.10…0.30,
    ///   precip 0.20…0.50, temp 32…40 or > 95, pitch 0.50…0.83, surface damp.
    /// else SAFE.
    static func assess(inputs: SafetyInputs) -> SafetyAssessment {
        var reasons: [String] = []
        var worst: SafetyRating = .safe

        func bump(_ to: SafetyRating, _ msg: String) {
            reasons.append(msg)
            if to == .unsafe || (to == .useCaution && worst == .safe) { worst = to }
        }

        if let g = inputs.windGustMph {
            if g > 25 { bump(.unsafe, "Wind gusts \(Int(g)) mph exceed 25 mph safe-roof limit") }
            else if g >= 15 { bump(.useCaution, "Wind gusts \(Int(g)) mph — exercise caution") }
        }
        if let s = inputs.sustainedWindMph {
            if s > 20 { bump(.unsafe, "Sustained wind \(Int(s)) mph exceeds 20 mph") }
            else if s >= 10 { bump(.useCaution, "Sustained wind \(Int(s)) mph — caution") }
        }
        if let l = inputs.lightningProbability01 {
            if l > 0.30 { bump(.unsafe, "Lightning probability \(Int(l * 100))% — do not climb") }
            else if l >= 0.10 { bump(.useCaution, "Lightning probability \(Int(l * 100))% — monitor sky") }
        }
        if let p = inputs.precipChance01 {
            if p > 0.50 { bump(.unsafe, "Precipitation likely (\(Int(p * 100))%)") }
            else if p >= 0.20 { bump(.useCaution, "Precipitation possible (\(Int(p * 100))%)") }
        }
        if let t = inputs.temperatureF {
            if t < 32 { bump(.unsafe, "Temperature \(Int(t))°F — risk of ice / brittle shingles") }
            else if t < 40 || t > 95 { bump(.useCaution, "Temperature \(Int(t))°F outside ideal range") }
        }
        if let r = inputs.pitchRatio {
            if r > 0.83 { bump(.unsafe, "Pitch \(pitchString(r)) exceeds 10/12 — require fall protection") }
            else if r >= 0.50 { bump(.useCaution, "Pitch \(pitchString(r)) is steep — use harness") }
        }
        if let s = inputs.surfaceDryness {
            switch s {
            case .wet, .icy: bump(.unsafe, "Surface is \(s.rawValue) — extreme slip risk")
            case .damp: bump(.useCaution, "Surface is damp")
            case .dry, .unknown: break
            }
        }

        return SafetyAssessment(
            rating: worst,
            reasons: reasons.isEmpty ? ["All measured conditions within safe range"] : reasons,
            computedAt: Date(),
            inputs: inputs
        )
    }

    private static func pitchString(_ r: Double) -> String {
        let rise = Int((r * 12).rounded())
        return "\(rise)/12"
    }
}

// MARK: - Presentation helpers

extension SafetyRating {
    nonisolated var label: String {
        switch self {
        case .safe: return "Safe to climb"
        case .useCaution: return "Use caution"
        case .unsafe: return "Unsafe — postpone"
        }
    }

    nonisolated var shortLabel: String {
        switch self {
        case .safe: return "Safe"
        case .useCaution: return "Caution"
        case .unsafe: return "Unsafe"
        }
    }

    nonisolated var symbolName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .useCaution: return "exclamationmark.triangle.fill"
        case .unsafe: return "xmark.octagon.fill"
        }
    }

    nonisolated var recommendation: String {
        switch self {
        case .safe: return "Conditions are within safe range for a roof inspection."
        case .useCaution: return "Proceed only with proper fall protection and a spotter."
        case .unsafe: return "Do not climb — reschedule until conditions improve."
        }
    }
}
