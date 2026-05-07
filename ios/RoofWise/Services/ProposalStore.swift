import Foundation
import Observation

@Observable
final class ProposalStore {
    static let shared = ProposalStore()

    private(set) var proposals: [Proposal] = []
    private let filename = "proposals.json"

    init() { load() }

    // MARK: CRUD

    @discardableResult
    func create(_ proposal: Proposal) -> Proposal {
        proposals.removeAll { $0.id == proposal.id }
        proposals.insert(proposal, at: 0)
        persist()
        return proposal
    }

    func update(_ proposal: Proposal) {
        guard let idx = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        var p = proposal
        p.updatedAt = .now
        proposals[idx] = p
        persist()
    }

    func markSent(id: UUID, channel: ProposalSentChannel, to recipient: String?) {
        guard let idx = proposals.firstIndex(where: { $0.id == id }) else { return }
        var p = proposals[idx]
        p.status = .sent
        p.sentChannel = channel
        p.sentTo = recipient
        p.sentAt = .now
        p.updatedAt = .now
        proposals[idx] = p
        persist()
    }

    func markViewed(id: UUID) {
        guard let idx = proposals.firstIndex(where: { $0.id == id }) else { return }
        var p = proposals[idx]
        if p.status == .sent { p.status = .viewed }
        p.viewedAt = .now
        p.updatedAt = .now
        proposals[idx] = p
        persist()
    }

    func markSigned(id: UUID, signature: Data?) {
        guard let idx = proposals.firstIndex(where: { $0.id == id }) else { return }
        var p = proposals[idx]
        p.status = .signed
        p.homeownerSignaturePng = signature
        p.signedAt = .now
        p.updatedAt = .now
        proposals[idx] = p
        persist()
    }

    func find(byJobId jobId: String) -> Proposal? {
        proposals.first { $0.originJobId == jobId }
    }

    var all: [Proposal] { proposals }

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
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let decoded = try? dec.decode([Proposal].self, from: data) {
            proposals = decoded
        }
    }

    private func persist() {
        guard let url = fileURL else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(proposals) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
