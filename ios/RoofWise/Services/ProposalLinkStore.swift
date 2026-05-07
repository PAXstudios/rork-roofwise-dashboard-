import Foundation
import Observation

nonisolated struct ProposalLinkRecord: Codable, Hashable, Sendable {
    let token: String
    let proposalId: UUID

    enum CodingKeys: String, CodingKey {
        case token
        case proposalId = "proposal_id"
    }
}

@Observable
final class ProposalLinkStore {
    static let shared = ProposalLinkStore()

    private(set) var records: [ProposalLinkRecord] = []
    private let filename = "proposal-links.json"

    init() { load() }

    /// Mints (or reuses) a short token for a proposal id.
    @discardableResult
    func mintToken(for proposalId: UUID) -> String {
        if let existing = records.first(where: { $0.proposalId == proposalId }) {
            return existing.token
        }
        let token = Self.makeShortToken()
        records.append(ProposalLinkRecord(token: token, proposalId: proposalId))
        persist()
        return token
    }

    func proposalId(forToken token: String) -> UUID? {
        records.first { $0.token == token }?.proposalId
    }

    func url(for proposalId: UUID) -> URL {
        let token = mintToken(for: proposalId)
        return URL(string: "https://roofwise.app/p/\(token)") ?? URL(fileURLWithPath: "/")
    }

    // MARK: Token

    private static func makeShortToken() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement() ?? "X" })
    }

    // MARK: Persistence

    private var fileURL: URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        return docs.appendingPathComponent(filename)
    }

    private func load() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([ProposalLinkRecord].self, from: data) {
            records = decoded
        }
    }

    private func persist() {
        guard let url = fileURL else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(records) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
