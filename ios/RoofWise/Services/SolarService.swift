import Foundation
import CoreLocation

// MARK: - Domain

nonisolated struct RoofSegmentMeasurement: Identifiable, Hashable, Sendable {
    let id: String
    /// Compass orientation label like "N", "NE", "E"…
    let orientation: String
    /// Pitch angle in degrees from horizontal.
    let pitchDegrees: Double
    /// Compass azimuth in degrees (0 = N, clockwise).
    let azimuthDegrees: Double
    /// Plane area in square feet.
    let areaSqFt: Double

    /// "Roof squares" = 100 sq ft (industry-standard estimating unit).
    var areaSquares: Double { areaSqFt / 100.0 }
    /// Convenience m² view for callers that want SI units.
    var areaM2: Double { areaSqFt / 10.7639 }

    /// Pitch expressed as rise-over-12 (rounded to nearest int).
    var pitchRiseOver12: Int {
        let rise = tan(pitchDegrees * .pi / 180.0) * 12.0
        return max(0, Int(rise.rounded()))
    }
}

nonisolated struct RoofMeasurements: Hashable, Sendable {
    let totalAreaSqFt: Double
    let segments: [RoofSegmentMeasurement]
    /// Approximate kWh/m²/yr at the roof (Google Solar `maxSunshineHoursPerYear`-derived).
    let sunshineKwhPerSqMPerYear: Double?
    /// Date of the imagery used to derive the measurement (Google "imageryDate").
    let imageryDate: Date?
    /// "Google Solar" or "Mock".
    let source: String
    let updatedAt: Date

    var totalAreaSquares: Double { totalAreaSqFt / 100.0 }
    /// Convenience m² view for callers that want SI units.
    var totalAreaM2: Double { totalAreaSqFt / 10.7639 }

    var dominantSegment: RoofSegmentMeasurement? {
        segments.max(by: { $0.areaSqFt < $1.areaSqFt })
    }
}

nonisolated enum SolarServiceError: Error {
    case missingKey
    case unavailable
    case underlying(Error)
}

// MARK: - Protocol

protocol SolarServicing: Sendable {
    var isLive: Bool { get }
    func measurements(at coord: CLLocationCoordinate2D) async throws -> RoofMeasurements
}

// MARK: - Mock impl

final class MockSolarService: SolarServicing, @unchecked Sendable {
    let isLive = false

    func measurements(at coord: CLLocationCoordinate2D) async throws -> RoofMeasurements {
        try? await Task.sleep(for: .milliseconds(140))
        return Self.measurements(for: coord, source: "Mock")
    }

    /// Deterministic synthesis — same coord always returns the same roof so
    /// the on-screen numbers are stable while we have no live key wired.
    static func measurements(for coord: CLLocationCoordinate2D, source: String) -> RoofMeasurements {
        let h = MockWeatherService.coordHash(coord)
        let total = 1800.0 + Double(h % 1600)              // 1,800-3,400 sq ft
        let basePitch = 18.0 + Double(h % 14)              // 18°-32°  (~5/12-7/12)
        let segCount = 3 + (h % 3)                         // 3, 4, or 5 segments
        let azStart  = Double(h % 90)                      // rotate the building

        let labels = ["N","NE","E","SE","S","SW","W","NW"]
        var segs: [RoofSegmentMeasurement] = []
        var remaining = total
        for i in 0..<segCount {
            // Distribute area in tapering shares so the dominant face reads
            // realistically (largest face is the front gable).
            let share: Double
            switch i {
            case 0:  share = 0.36
            case 1:  share = 0.28
            case 2:  share = 0.20
            case 3:  share = 0.10
            default: share = 0.06
            }
            let area = (i == segCount - 1) ? remaining : (total * share)
            remaining -= area
            let azimuth = (azStart + Double(i) * 360.0 / Double(segCount))
                .truncatingRemainder(dividingBy: 360)
            let pitchJitter = Double((h &+ i * 17) % 5) - 2.0   // ±2°
            let label = labels[Int((azimuth / 45.0).rounded()) % labels.count]
            segs.append(.init(
                id: "mock-\(i)",
                orientation: label,
                pitchDegrees: basePitch + pitchJitter,
                azimuthDegrees: azimuth,
                areaSqFt: area
            ))
        }

        return RoofMeasurements(
            totalAreaSqFt: total,
            segments: segs,
            sunshineKwhPerSqMPerYear: 1450 + Double(h % 350),
            imageryDate: Calendar.current.date(byAdding: .month, value: -((h % 18) + 1), to: .now),
            source: source,
            updatedAt: .now
        )
    }
}

// MARK: - Live impl (Google Solar API: buildingInsights:findClosest)

final class LiveSolarService: SolarServicing, @unchecked Sendable {
    let isLive = true

    private let session: URLSession
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: cfg)
    }

    func measurements(at coord: CLLocationCoordinate2D) async throws -> RoofMeasurements {
        guard !apiKey.isEmpty else {
            throw SolarServiceError.missingKey
        }
        var comps = URLComponents(string: "https://solar.googleapis.com/v1/buildingInsights:findClosest")!
        comps.queryItems = [
            .init(name: "location.latitude",  value: String(coord.latitude)),
            .init(name: "location.longitude", value: String(coord.longitude)),
            .init(name: "requiredQuality",    value: "HIGH"),
            .init(name: "key",                value: apiKey)
        ]
        guard let url = comps.url else {
            throw SolarServiceError.unavailable
        }

        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
                print("[SolarService] Live error \(status) \(body)")
                throw SolarServiceError.unavailable
            }
            let dto = try JSONDecoder().decode(BuildingInsightsDTO.self, from: data)
            if let m = dto.toMeasurements() { return m }
            throw SolarServiceError.unavailable
        } catch let e as SolarServiceError {
            throw e
        } catch {
            throw SolarServiceError.underlying(error)
        }
    }
}

// MARK: - Factory

enum SolarServiceFactory {
    static let shared: SolarServicing = {
        if APIKeys.isLiveGoogleSolar {
            return LiveSolarService(apiKey: APIKeys.googleSolarApiKey)
        }
        return MockSolarService()
    }()
}

// MARK: - Google Solar DTO

private nonisolated struct BuildingInsightsDTO: Decodable {
    let imageryDate: ImageryDate?
    let solarPotential: SolarPotential?

    struct ImageryDate: Decodable {
        let year: Int?; let month: Int?; let day: Int?
    }
    struct SolarPotential: Decodable {
        let maxSunshineHoursPerYear: Double?
        let wholeRoofStats: SizeStats?
        let roofSegmentStats: [RoofSegmentDTO]?
    }
    struct SizeStats: Decodable {
        let areaMeters2: Double?
    }
    struct RoofSegmentDTO: Decodable {
        let pitchDegrees: Double?
        let azimuthDegrees: Double?
        let stats: SizeStats?
    }

    func toMeasurements() -> RoofMeasurements? {
        guard let pot = solarPotential else { return nil }
        let totalSqFt: Double = {
            if let m2 = pot.wholeRoofStats?.areaMeters2 { return m2 * 10.7639 }
            let segSum = (pot.roofSegmentStats ?? []).compactMap { $0.stats?.areaMeters2 }.reduce(0, +)
            return segSum * 10.7639
        }()
        guard totalSqFt > 0 else { return nil }

        let labels = ["N","NE","E","SE","S","SW","W","NW"]
        let segs: [RoofSegmentMeasurement] = (pot.roofSegmentStats ?? [])
            .enumerated()
            .compactMap { idx, s in
                guard let m2 = s.stats?.areaMeters2 else { return nil }
                let az = s.azimuthDegrees ?? 0
                let pitch = s.pitchDegrees ?? 0
                let label = labels[Int((az / 45.0).rounded()) % labels.count]
                return RoofSegmentMeasurement(
                    id: "seg-\(idx)",
                    orientation: label,
                    pitchDegrees: pitch,
                    azimuthDegrees: az,
                    areaSqFt: m2 * 10.7639
                )
            }
            .sorted { $0.areaSqFt > $1.areaSqFt }

        let sunshine: Double? = pot.maxSunshineHoursPerYear.map { $0 * 0.9 } // crude kWh/m² proxy

        var imagery: Date? = nil
        if let i = imageryDate, let y = i.year, let m = i.month, let d = i.day {
            imagery = Calendar(identifier: .gregorian).date(from:
                DateComponents(year: y, month: m, day: d))
        }

        return RoofMeasurements(
            totalAreaSqFt: totalSqFt,
            segments: segs,
            sunshineKwhPerSqMPerYear: sunshine,
            imageryDate: imagery,
            source: "Google Solar",
            updatedAt: .now
        )
    }
}
