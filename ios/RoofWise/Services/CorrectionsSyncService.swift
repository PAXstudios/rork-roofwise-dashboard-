import Foundation
import Observation

@Observable
final class CorrectionsSyncService {
    static let shared = CorrectionsSyncService()

    private let syncEnabledKey = "roofwise.syncCorrectionsEnabled"
    private let filename = "corrections_outbox.json"
    private(set) var lastSyncMessage: String? = nil

    private init() {}

    var isSyncEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: syncEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: syncEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }

    func enqueue(_ correction: CorrectionExport) {
        writeMockOutbox(appending: correction)
        guard isSyncEnabled else {
            lastSyncMessage = "Correction saved locally. Cloud sync is off."
            return
        }
        if APIKeys.USE_MOCKS {
            lastSyncMessage = "Mock sync queued to corrections_outbox.json"
        } else {
            lastSyncMessage = "Queued for upload to RoofWise corrections endpoint"
        }
    }

    func writeMockOutbox(appending correction: CorrectionExport) {
        var outbox = loadOutbox()
        outbox.append(correction)
        persist(outbox)
    }

    func loadOutbox() -> [CorrectionExport] {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CorrectionExport].self, from: data)) ?? []
    }

    private func persist(_ outbox: [CorrectionExport]) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(outbox)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("CorrectionsSyncService persist failed: \(error)")
            #endif
        }
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }
}
