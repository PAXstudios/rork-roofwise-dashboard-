import SwiftUI
import Observation
import CoreLocation

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
        scheduleGeocode(for: customer.id)
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

    /// Creates (or updates) a Customer record that mirrors a HAAG `Inspection`
    /// created in the New Job wizard, so the job is visible and reachable from
    /// the Leads list and can open its inspection report. Matches an existing
    /// customer by linked report id, then by address, before inserting a new one.
    @discardableResult
    func upsertFromInspection(_ insp: Inspection,
                              phone: String = "",
                              email: String = "",
                              makeActive: Bool = true) -> UUID {
        let job = insp.job
        let name = job.clientName.trimmingCharacters(in: .whitespaces)
        let addr = job.propertyAddress.trimmingCharacters(in: .whitespaces)

        func matchIndex() -> Int? {
            if let i = customers.firstIndex(where: { $0.linkedReportId == job.reportId }) {
                return i
            }
            guard !addr.isEmpty else { return nil }
            return customers.firstIndex {
                $0.linkedReportId == nil &&
                $0.address.localizedCaseInsensitiveContains(addr)
            }
        }

        if let i = matchIndex() {
            if !name.isEmpty { customers[i].ownerName = name }
            if !addr.isEmpty { customers[i].address = addr }
            if !phone.isEmpty { customers[i].phone = phone }
            if !email.isEmpty { customers[i].email = email }
            if !job.carrierName.isEmpty { customers[i].insuranceCompany = job.carrierName }
            if !job.policyNumber.isEmpty { customers[i].policyNumber = job.policyNumber }
            customers[i].linkedReportId = job.reportId
            if customers[i].stage.stepIndex < JobPipelineStage.inspectionScheduled.stepIndex {
                customers[i].stage = .inspectionScheduled
            }
            if makeActive { activeCustomerID = customers[i].id }
            return customers[i].id
        }

        var c = Customer(
            ownerName: name.isEmpty ? "New Job" : name,
            address: addr,
            phone: phone,
            email: email,
            insuranceCompany: job.carrierName,
            policyNumber: job.policyNumber,
            stage: .inspectionScheduled,
            stormTagged: insp.event.hasHail || insp.event.hasWind
        )
        // Reuse coords already geocoded onto the inspection, if any.
        c.latitude = insp.job.latitude
        c.longitude = insp.job.longitude
        c.linkedReportId = job.reportId
        customers.append(c)
        if makeActive { activeCustomerID = c.id }
        scheduleGeocode(for: c.id)
        return c.id
    }

    func updateStage(_ id: UUID, to stage: JobPipelineStage) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].stage = stage
    }

    // MARK: - Geocoded location

    /// Persist a resolved coordinate onto the customer (used on creation and by
    /// the one-time backfill migration).
    func setCoordinate(_ coord: CLLocationCoordinate2D, for id: UUID) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].latitude = coord.latitude
        customers[i].longitude = coord.longitude
    }

    /// Geocode a newly-created customer's address in the background (cache-first)
    /// and store the coordinate so its map pin lands on the real address.
    private func scheduleGeocode(for id: UUID) {
        Task { [weak self] in
            guard let self,
                  let customer = self.customers.first(where: { $0.id == id }),
                  customer.coordinate == nil, !customer.isUnassignedDraft else { return }
            if let coord = await CoordinateBackfillService.shared.resolve(address: customer.address) {
                self.setCoordinate(coord, for: id)
            }
        }
    }

    // MARK: - Roof measurement + repair estimate (background)

    func setEstimating(_ id: UUID, _ value: Bool) {
        guard let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].isEstimating = value
    }

    /// Persist a background Google Solar measurement + cost estimate onto the
    /// customer. Also stamps a compact `estimatedValue` string used by the lead
    /// card + profile header capsules.
    func applyRoofEstimate(customerID: UUID,
                           measurement: RoofMeasurements,
                           estimate: CostEstimate) {
        guard let i = customers.firstIndex(where: { $0.id == customerID }) else { return }
        customers[i].roofSquares = measurement.totalAreaSquares
        customers[i].roofSegments = measurement.segments.count
        customers[i].roofMeasurementSource = measurement.source
        customers[i].estimateLow = estimate.low
        customers[i].estimateHigh = estimate.high
        customers[i].estimatePerSquare = estimate.pricePerSquare
        customers[i].estimateMaterialName = estimate.input.material.displayName
        customers[i].estimatedValue = RoofEstimateService.compactRange(low: estimate.low, high: estimate.high)
        customers[i].isEstimating = false
    }

    func appendPhotos(_ photos: [CapturedPhoto], to id: UUID) {
        guard !photos.isEmpty, let i = customers.firstIndex(where: { $0.id == id }) else { return }
        customers[i].photos.append(contentsOf: photos)
        if customers[i].stage.stepIndex < JobPipelineStage.inspectionComplete.stepIndex {
            customers[i].stage = .inspectionComplete
        }
        Task { await PhotoSyncService.shared.sync(photos, for: id) }
    }

    /// Replace a single photo (matched by id) in place — used by the background
    /// mass-analysis service so the profile reflects each photo as it lands.
    func replacePhoto(_ photo: CapturedPhoto, for id: UUID) {
        guard let i = customers.firstIndex(where: { $0.id == id }),
              let pIdx = customers[i].photos.firstIndex(where: { $0.id == photo.id }) else { return }
        customers[i].photos[pIdx] = photo
        Task { await PhotoSyncService.shared.sync([photo], for: id) }
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
        scheduleGeocode(for: new.id)
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
