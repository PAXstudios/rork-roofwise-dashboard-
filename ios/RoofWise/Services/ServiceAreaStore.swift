import Foundation
import Observation
import CoreLocation

@Observable
final class ServiceAreaStore {
    static let shared = ServiceAreaStore()

    private(set) var areas: [ServiceArea] = []
    private let filename = "service-areas.json"
    private let geocoder: GeocodingService

    init(geocoder: GeocodingService = GeocodingServiceFactory.shared) {
        self.geocoder = geocoder
        load()
    }

    var all: [ServiceArea] { areas }
    var hasConfiguredServiceArea: Bool { !areas.isEmpty }

    @discardableResult
    func add(_ area: ServiceArea) -> ServiceArea {
        // De-dupe by normalized label.
        let key = area.label.lowercased()
        if let existing = areas.first(where: { $0.label.lowercased() == key }) {
            return existing
        }
        areas.insert(area, at: 0)
        persist()
        // Best-effort geocode in background.
        let id = area.id
        let label = area.label
        Task { [weak self] in
            guard let self else { return }
            let coord = try? await geocoder.geocode(label)
            guard let coord else { return }
            await MainActor.run {
                if let idx = self.areas.firstIndex(where: { $0.id == id }) {
                    self.areas[idx].centerLat = coord.latitude
                    self.areas[idx].centerLng = coord.longitude
                    self.persist()
                }
            }
        }
        return area
    }

    func remove(id: UUID) {
        areas.removeAll { $0.id == id }
        persist()
    }

    func contains(zip: String) -> Bool {
        areas.contains { $0.zip == zip }
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
        if let arr = try? dec.decode([ServiceArea].self, from: data) {
            areas = arr
        }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(areas) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
