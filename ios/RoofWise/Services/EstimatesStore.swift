import Foundation
import Observation

// MARK: - Persisted record

nonisolated struct SavedEstimate: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var address: String
    var savedAt: Date

    // Snapshotted CostEstimateInput fields (so an old estimate can be
    // reconstructed even if the engine math drifts).
    var totalSquares: Double
    var detectedSegmentCount: Int
    var avgPitchRiseOver12: Int
    var materialRaw: String
    var qualityRaw: String
    var complexityRaw: String
    var tearOffLayers: Int
    var includePermit: Bool
    var includeDisposal: Bool

    // Snapshotted result.
    var subtotal: Double
    var low: Double
    var high: Double
    var pricePerSquare: Double
    var region: String

    init(from est: CostEstimate, address: String, region: String = "TX") {
        self.id = UUID()
        self.address = address
        self.savedAt = .now
        self.totalSquares = est.input.totalSquares
        self.detectedSegmentCount = est.input.detectedSegmentCount
        self.avgPitchRiseOver12 = est.input.avgPitchRiseOver12
        self.materialRaw = est.input.material.rawValue
        self.qualityRaw = est.input.quality.rawValue
        self.complexityRaw = est.input.complexity.rawValue
        self.tearOffLayers = est.input.tearOffLayers
        self.includePermit = est.input.includePermit
        self.includeDisposal = est.input.includeDisposal
        self.subtotal = est.subtotal
        self.low = est.low
        self.high = est.high
        self.pricePerSquare = est.pricePerSquare
        self.region = region
    }

    var material: EstimateMaterial { EstimateMaterial(rawValue: materialRaw) ?? .asphaltArch }
    var quality:  EstimateQuality  { EstimateQuality(rawValue: qualityRaw) ?? .better }
    var complexity: EstimateComplexity { EstimateComplexity(rawValue: complexityRaw) ?? .average }

    var rangeLabel: String { "\(currency(low)) – \(currency(high))" }

    /// Reconstruct a `CostEstimate` so the wizard can re-display this saved
    /// record at Step 4 with the same look as a freshly-computed one.
    var estimate: CostEstimate {
        let input = CostEstimateInput(
            address: address,
            totalSquares: totalSquares,
            detectedSegmentCount: detectedSegmentCount,
            avgPitchRiseOver12: avgPitchRiseOver12,
            material: material,
            quality: quality,
            complexity: complexity,
            tearOffLayers: tearOffLayers,
            includePermit: includePermit,
            includeDisposal: includeDisposal
        )
        return CostEstimator.estimate(input)
    }
}

// MARK: - Store

@Observable
final class EstimatesStore {
    static let shared = EstimatesStore()

    private(set) var estimates: [SavedEstimate] = []
    private let filename = "estimates.json"

    init() { load() }

    func save(_ est: SavedEstimate) {
        // Replace any prior estimate for the same address — the most recent
        // run is what matters in the Saved strip.
        estimates.removeAll { $0.address == est.address }
        estimates.insert(est, at: 0)
        persist()
    }

    func remove(id: UUID) {
        estimates.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        estimates.removeAll()
        persist()
    }

    // MARK: Persistence

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(filename)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let arr = try? dec.decode([SavedEstimate].self, from: data) {
            estimates = arr
        }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(estimates) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
