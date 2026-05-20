import Foundation
import Observation
import Supabase

/// Sync status surfaced to the Leads UI.
enum LeadsSyncStatus: Equatable {
    case idle
    case syncing
    case synced(at: Date)
    case failed(message: String)
}

/// Local-first sync between `CustomerStore` (UI source of truth) and the
/// Supabase `leads` table. Pushes pending local changes up and pulls remote
/// changes down. Only operates when a user is signed in.
@Observable
@MainActor
final class LeadsSyncService {
    static let shared = LeadsSyncService()

    private(set) var status: LeadsSyncStatus = .idle
    private(set) var pendingCount: Int = 0

    /// Per-customer hashes of the last-synced server state, used to detect
    /// local changes that still need pushing.
    private var syncedHashes: [UUID: Int] = [:]
    private var inFlight: Bool = false

    private init() {}

    /// Inject the CustomerStore so the sync can read/write it. Call once at app
    /// start (after RootView is mounted).
    private var customerStoreRef: CustomerStore?
    func attach(_ store: CustomerStore) {
        customerStoreRef = store
    }

    /// Trigger a full sync: pull remote rows, then push any local changes.
    func syncNow() async {
        guard !inFlight else { return }
        guard let store = customerStoreRef else { return }
        guard AuthStore.shared.currentUserId != nil else {
            status = .idle
            return
        }
        inFlight = true
        status = .syncing
        defer { inFlight = false }

        do {
            try await pullRemote(into: store)
            try await pushLocal(from: store)
            status = .synced(at: Date())
            recomputePendingCount(from: store)
        } catch {
            print("[LeadsSync] failed: \(error)")
            status = .failed(message: Self.friendlyMessage(for: error))
            recomputePendingCount(from: store)
        }
    }

    /// Recompute pending count from the current store. Called whenever the UI
    /// adds/edits a lead.
    func noteLocalChange() {
        guard let store = customerStoreRef else { return }
        recomputePendingCount(from: store)
    }

    private func recomputePendingCount(from store: CustomerStore) {
        var count = 0
        for c in store.customers where !c.isUnassignedDraft {
            if syncedHashes[c.id] != Self.hash(of: c) { count += 1 }
        }
        pendingCount = count
    }

    // MARK: - Remote ↔ local

    private func pullRemote(into store: CustomerStore) async throws {
        let rows: [RemoteLead] = try await SupabaseService.client
            .from("leads")
            .select()
            .execute()
            .value

        for row in rows {
            guard let id = UUID(uuidString: row.id) else { continue }
            let mapped = row.toCustomer(id: id)
            if let i = store.customers.firstIndex(where: { $0.id == id }) {
                // Only overwrite if remote is meaningfully different (preserves local typing).
                if Self.hash(of: store.customers[i]) != Self.hash(of: mapped) {
                    store.customers[i] = mapped
                }
            } else {
                store.customers.append(mapped)
            }
            syncedHashes[id] = Self.hash(of: mapped)
        }
    }

    private func pushLocal(from store: CustomerStore) async throws {
        guard let userId = AuthStore.shared.currentUserId else { return }
        var pending: [RemoteLead] = []
        for c in store.customers {
            if c.isUnassignedDraft { continue }
            let h = Self.hash(of: c)
            if syncedHashes[c.id] == h { continue }
            pending.append(RemoteLead.from(customer: c, userId: userId))
        }
        guard !pending.isEmpty else { return }

        try await SupabaseService.client
            .from("leads")
            .upsert(pending, onConflict: "id")
            .execute()

        // Mark these as synced.
        for row in pending {
            if let id = UUID(uuidString: row.id) {
                syncedHashes[id] = Self.hash(of: row.toCustomer(id: id))
            }
        }
    }

    /// Reset the local sync ledger (e.g. on sign-out).
    func resetLedger() {
        syncedHashes.removeAll()
        pendingCount = 0
        status = .idle
    }

    // MARK: - Helpers

    private static func hash(of c: Customer) -> Int {
        var hasher = Hasher()
        hasher.combine(c.ownerName)
        hasher.combine(c.address)
        hasher.combine(c.phone)
        hasher.combine(c.email)
        hasher.combine(c.insuranceCompany)
        hasher.combine(c.policyNumber)
        hasher.combine(c.adjusterName)
        hasher.combine(c.adjusterPhone)
        hasher.combine(c.stage.rawValue)
        hasher.combine(c.stormTagged)
        hasher.combine(c.estimatedValue)
        hasher.combine(c.claimPacketSummary)
        return hasher.finalize()
    }

    private static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("network") || raw.contains("offline") || raw.contains("internet") {
            return "Offline — will retry when you're back online."
        }
        if raw.contains("jwt") || raw.contains("not authenticated") {
            return "Session expired — please sign in again."
        }
        return "Sync failed: \(error.localizedDescription)"
    }
}

// MARK: - Remote row DTO

nonisolated struct RemoteLead: Codable, Sendable {
    let id: String
    let user_id: String
    let owner_name: String
    let address: String
    let phone: String
    let email: String
    let insurance_company: String
    let policy_number: String
    let date_of_loss: Date?
    let adjuster_name: String
    let adjuster_phone: String
    let stage: String
    let storm_tagged: Bool
    let estimated_value: String
    let claim_packet_summary: String
    let updated_at: Date?

    static func from(customer c: Customer, userId: String) -> RemoteLead {
        RemoteLead(
            id: c.id.uuidString,
            user_id: userId,
            owner_name: c.ownerName,
            address: c.address,
            phone: c.phone,
            email: c.email,
            insurance_company: c.insuranceCompany,
            policy_number: c.policyNumber,
            date_of_loss: c.dateOfLoss,
            adjuster_name: c.adjusterName,
            adjuster_phone: c.adjusterPhone,
            stage: c.stage.rawValue,
            storm_tagged: c.stormTagged,
            estimated_value: c.estimatedValue,
            claim_packet_summary: c.claimPacketSummary,
            updated_at: Date()
        )
    }

    func toCustomer(id: UUID) -> Customer {
        Customer(
            ownerName: owner_name,
            address: address,
            phone: phone,
            email: email,
            insuranceCompany: insurance_company,
            policyNumber: policy_number,
            dateOfLoss: date_of_loss,
            adjusterName: adjuster_name,
            adjusterPhone: adjuster_phone,
            stage: JobPipelineStage(rawValue: stage) ?? .knocked,
            stormTagged: storm_tagged,
            estimatedValue: estimated_value,
            claimPacketSummary: claim_packet_summary
        )
    }
}
