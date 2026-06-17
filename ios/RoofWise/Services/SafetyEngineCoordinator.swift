import Foundation
import CoreLocation

// MARK: - Safety Engine Coordinator
//
// Bridges live RoofWise data (Google Weather + Google Solar roof pitch) into the
// pure `SafetyEngine`. Missing signals stay `nil` so the engine reasons over what
// it actually has rather than fabricating values.

@Observable
final class SafetyEngineCoordinator {
    static let shared = SafetyEngineCoordinator()

    private let weather: WeatherServicing = WeatherServiceFactory.shared
    private let solar: SolarServicing = SolarServiceFactory.shared

    /// Computes a roof-walk safety assessment for an inspection at a coordinate.
    func assess(at coordinate: CLLocationCoordinate2D) async -> SafetyAssessment {
        let snapshot = try? await weather.currentConditions(at: coordinate)
        let measurements = try? await solar.measurements(at: coordinate)
        let inputs = makeInputs(snapshot: snapshot, measurements: measurements)
        return SafetyEngine.assess(inputs: inputs)
    }

    /// Convenience: resolve an inspection's address to a coordinate, then assess.
    func assessForInspection(_ insp: Inspection) async -> SafetyAssessment {
        let coord = WeatherServiceFactory.mockCoord(forAddress: insp.job.propertyAddress)
        return await assess(at: coord)
    }

    // MARK: - Input composition

    private func makeInputs(snapshot: WeatherSnapshot?,
                            measurements: RoofMeasurements?) -> SafetyInputs {
        let pitchRatio: Double? = measurements?.dominantSegment.map { seg in
            tan(seg.pitchDegrees * .pi / 180.0)
        }
        let precip01: Double? = snapshot.map { snap in
            Double(snap.precipProbabilityPct ?? snap.hailRiskPct) / 100.0
        }
        let lightning01: Double? = snapshot?.lightningProbabilityPct.map { Double($0) / 100.0 }

        return SafetyInputs(
            windGustMph: snapshot?.windGustMph.map(Double.init),
            sustainedWindMph: snapshot.map { Double($0.windMph) },
            precipChance01: precip01,
            lightningProbability01: lightning01,
            temperatureF: snapshot.map { Double($0.temperatureF) },
            pitchRatio: pitchRatio,
            surfaceDryness: snapshot.map { Self.surfaceDryness(for: $0.condition) }
        )
    }

    /// Infers surface wetness from the weather condition text. Conservative —
    /// when unclear it returns `.unknown` so the engine doesn't over-flag.
    private static func surfaceDryness(for condition: String) -> SurfaceDryness {
        let c = condition.lowercased()
        if c.contains("snow") || c.contains("ice") || c.contains("sleet") || c.contains("freez") {
            return .icy
        }
        if c.contains("rain") || c.contains("storm") || c.contains("thunder") || c.contains("shower") {
            return .wet
        }
        if c.contains("drizzle") || c.contains("mist") || c.contains("fog") {
            return .damp
        }
        if c.contains("sun") || c.contains("clear") || c.contains("cloud") || c.contains("haz") {
            return .dry
        }
        return .unknown
    }
}
