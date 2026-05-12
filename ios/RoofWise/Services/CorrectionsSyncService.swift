import Foundation
import Observation

/// Phase 9E corrections sync. Real behavior: every `Correction` write is
/// appended (JSONL) to `corrections_outbox.json` in Application Support.
/// The actual cloud POST is stubbed — the outbox file is the evidence.
/// Rotates at 5 MB to `corrections_outbox.json.1`.
@Observable
final class CorrectionsSyncService {
    static let shared = CorrectionsSyncService()

    private let outboxName = "corrections_outbox.json"
    private let rotateName = "corrections_outbox.json.1"
    private let maxBytes: Int = 5 * 1024 * 1024

    /// User-facing toggle bound in Settings. Defaults to `true`.
    var syncEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: Self.toggleKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.toggleKey) }
    }
    static let toggleKey = "syncCorrectionsToCloud"

    private init() {}

    private var outboxURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return base.appendingPathComponent(outboxName)
    }

    private var rotateURL: URL? {
        outboxURL?.deletingLastPathComponent().appendingPathComponent(rotateName)
    }

    /// Append a JSON-serialized correction (one per line) to the outbox.
    func enqueueOutbox(_ correction: Correction) {
        guard syncEnabled else { return }
        guard let url = outboxURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(correction) else { return }
        line.append(0x0A) // newline

        rotateIfNeeded(url: url, incoming: line.count)

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } catch {
                    #if DEBUG
                    print("CorrectionsSyncService append failed: \(error)")
                    #endif
                }
            }
        } else {
            try? line.write(to: url, options: .atomic)
        }
        #if DEBUG
        print("[CorrectionsSyncService] queued correction \(correction.id.uuidString.prefix(8)) → \(url.lastPathComponent)")
        #endif
    }

    private func rotateIfNeeded(url: URL, incoming: Int) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue else { return }
        guard size + incoming > maxBytes else { return }
        guard let rotate = rotateURL else { return }
        try? FileManager.default.removeItem(at: rotate)
        try? FileManager.default.moveItem(at: url, to: rotate)
    }
}
