import SwiftUI
import Observation

@Observable
final class CustomerStore {
    var customers: [Customer]
    var activeCustomerID: UUID?

    init() {
        // Clean empty state — no seeded sample customers. Real records come
        // from door-knocking, inspection drafts, and address lookups.
        self.customers = []
        self.activeCustomerID = nil
    }

    var activeCustomer: Customer? {
        get { customers.first { $0.id == activeCustomerID } }
        set {
            guard let nv = newValue, let i = customers.firstIndex(where: { $0.id == nv.id }) else { return }
            customers[i] = nv
        }
    }

    func setActive(_ id: UUID) {
        activeCustomerID = id
    }

    func add(_ customer: Customer, makeActive: Bool = true) {
        customers.append(customer)
        if makeActive { activeCustomerID = customer.id }
    }

    /// Creates a lightweight placeholder customer for an inspection where the
    /// user wants to capture photos first and assign a real property later.
    /// Returns the new customer's id (and sets it as active).
    @discardableResult
    func createUnassignedDraft() -> UUID {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        let stamp = f.string(from: Date())
        let draft = Customer(
            ownerName: "Unassigned Inspection",
            address: "Add property \u{2022} \(stamp)",
            stage: .inspectionScheduled,
            stormTagged: false,
            estimatedValue: ""
        )
        customers.append(draft)
        activeCustomerID = draft.id
        return draft.id
    }

    func update(_ customer: Customer) {
        guard let i = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        customers[i] = customer
    }

    func updateStage(_ id: UUID, to stage: JobPipelineStage) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].stage = stage
    }

    func appendPhotos(_ photos: [CapturedPhoto], to id: UUID) {
        guard !photos.isEmpty, let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].photos.append(contentsOf: photos)
        if customers[i].stage.stepIndex < JobPipelineStage.inspectionComplete.stepIndex {
            customers[i].stage = .inspectionComplete
        }
        Task { await PhotoSyncService.shared.sync(photos, for: id) }
    }

    func updateAnalysis(for id: UUID, photos: [CapturedPhoto], findings: [InspectionFinding]) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        // Replace photos that match by id with their analyzed counterparts; append new
        var existing = customers[i].photos
        for p in photos {
            if let idx = existing.firstIndex(where: { $0.id == p.id }) {
                existing[idx] = p
            } else {
                existing.append(p)
            }
        }
        customers[i].photos = existing
        customers[i].damageFindings = findings
        Task { await PhotoSyncService.shared.sync(photos, for: id) }
    }

    func attachClaim(for id: UUID, packet: ClaimPacket) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].claimGrade = packet.grade
        customers[i].claimPacketSummary = packet.summary
        if customers[i].stage.stepIndex < JobPipelineStage.claimFiled.stepIndex {
            customers[i].stage = .claimFiled
        }
    }

    /// Find an existing customer matching the recent-job address (street prefix match),
    /// or create a new lightweight customer from the recent job and return its id.
    func resolveCustomer(for job: RecentJob) -> UUID {
        let jobStreet = job.address.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? job.address
        if let match = customers.first(where: { c in
            jobStreet.localizedCaseInsensitiveContains(c.address) ||
            c.address.localizedCaseInsensitiveContains(jobStreet) ||
            c.ownerName.localizedCaseInsensitiveContains(job.title) ||
            job.title.localizedCaseInsensitiveContains(c.ownerName)
        }) {
            return match.id
        }
        let stage: JobPipelineStage = {
            switch job.status {
            case .done: return .paid
            case .active: return .materialOrdered
            case .scheduled: return .inspectionScheduled
            case .awaiting: return .adjusterMeeting
            }
        }()
        let new = Customer(
            ownerName: job.title,
            address: jobStreet,
            stage: stage,
            stormTagged: job.status == .awaiting,
            estimatedValue: ""
        )
        customers.append(new)
        return new.id
    }

    func addNote(_ text: String, to id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].notes.insert(CustomerNote(text: trimmed), at: 0)
    }

    /// Log a homeowner-recap share to the customer's timeline and bump
    /// pipeline stage from Inspection Complete → Recap Sent if applicable.
    func logHomeownerShare(channel: HomeownerShareChannel, to id: UUID) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let timeStr = f.string(from: Date())
        let entry = "Recap sent via \(channel.rawValue) — \(timeStr)"
        customers[i].notes.insert(CustomerNote(text: entry), at: 0)
        if customers[i].stage == .inspectionComplete {
            customers[i].stage = .recapSent
        }
    }
}

// MARK: - Homeowner Share Channel

enum HomeownerShareChannel: String, CaseIterable, Identifiable, Codable {
    case messages = "Messages"
    case mail = "Mail"
    case airdrop = "AirDrop"
    case shareSheet = "Share Sheet"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .messages: return "message.fill"
        case .mail: return "envelope.fill"
        case .airdrop: return "dot.radiowaves.left.and.right"
        case .shareSheet: return "square.and.arrow.up"
        }
    }

    var tint: Color {
        switch self {
        case .messages: return Theme.mint
        case .mail: return Theme.sky
        case .airdrop: return Theme.amber
        case .shareSheet: return Theme.ember
        }
    }

    var shortLabel: String {
        switch self {
        case .messages: return "Text"
        case .mail: return "Email"
        case .airdrop: return "AirDrop"
        case .shareSheet: return "Share…"
        }
    }
}
