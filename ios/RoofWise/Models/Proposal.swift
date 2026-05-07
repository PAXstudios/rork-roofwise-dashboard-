import Foundation

// MARK: - Line item

nonisolated enum ProposalLineItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case tearOff         = "tear_off"
    case decking
    case underlayment
    case iceWaterShield  = "ice_water_shield"
    case dripEdge        = "drip_edge"
    case ridge
    case valley
    case shingles
    case ventilation
    case gutters
    case flashing
    case labor
    case other

    var displayName: String {
        switch self {
        case .tearOff:        return "Tear-off"
        case .decking:        return "Decking"
        case .underlayment:   return "Underlayment"
        case .iceWaterShield: return "Ice & Water Shield"
        case .dripEdge:       return "Drip Edge"
        case .ridge:          return "Ridge"
        case .valley:         return "Valley"
        case .shingles:       return "Shingles"
        case .ventilation:    return "Ventilation"
        case .gutters:        return "Gutters"
        case .flashing:       return "Flashing"
        case .labor:          return "Labor"
        case .other:          return "Other"
        }
    }

    /// Default unit token used by the generator and unit chip selector.
    var defaultUnit: String {
        switch self {
        case .tearOff, .underlayment, .iceWaterShield, .decking, .shingles:
            return "sq"
        case .dripEdge, .ridge, .valley, .gutters, .flashing:
            return "lf"
        case .ventilation:
            return "ea"
        case .labor:
            return "hr"
        case .other:
            return "ea"
        }
    }
}

nonisolated struct ProposalLineItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: ProposalLineItemKind
    var label: String
    var quantity: Double
    var unit: String
    var unitPrice: Double

    var totalPrice: Double { quantity * unitPrice }

    init(id: UUID = UUID(),
         kind: ProposalLineItemKind,
         label: String? = nil,
         quantity: Double,
         unit: String? = nil,
         unitPrice: Double) {
        self.id = id
        self.kind = kind
        self.label = label ?? kind.displayName
        self.quantity = quantity
        self.unit = unit ?? kind.defaultUnit
        self.unitPrice = unitPrice
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, label, quantity, unit
        case unitPrice = "unit_price"
    }
}

// MARK: - Status / channel

nonisolated enum ProposalStatus: String, Codable, Hashable, Sendable {
    case draft, sent, viewed, signed, declined, expired

    var displayName: String {
        switch self {
        case .draft:    return "DRAFT"
        case .sent:     return "SENT"
        case .viewed:   return "VIEWED"
        case .signed:   return "SIGNED"
        case .declined: return "DECLINED"
        case .expired:  return "EXPIRED"
        }
    }
}

nonisolated enum ProposalSentChannel: String, Codable, Hashable, Sendable {
    case email, sms, link
}

// MARK: - Proposal

nonisolated struct Proposal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var originJobId: String                  // Job/report id used by JobDetailView
    var originInspectionId: String           // Inspection.report_id; kept explicit for proposal links/audits
    var originEstimateId: String?            // SavedEstimate.id (uuid string)
    var homeownerName: String
    var projectAddress: String
    var lineItems: [ProposalLineItem]

    var taxRate: Double                      // 0.0825
    var depositRate: Double                  // 0.30
    var scopeNarrative: String
    var warrantyTerms: String
    var paymentSchedule: String
    var validUntil: Date

    var status: ProposalStatus
    var homeownerSignaturePng: Data?
    var sentTo: String?
    var sentChannel: ProposalSentChannel?
    var sentAt: Date?
    var viewedAt: Date?
    var signedAt: Date?
    var declinedAt: Date?

    var createdAt: Date
    var updatedAt: Date

    // MARK: Computed totals

    var subtotal: Double { lineItems.reduce(0) { $0 + $1.totalPrice } }
    var tax: Double { subtotal * taxRate }
    var total: Double { subtotal + tax }
    var depositAmount: Double { total * depositRate }

    /// Backward-compatible alias retained for Phase 7 call sites and older JSON (`deposit_pct`).
    var depositPct: Double {
        get { depositRate }
        set { depositRate = newValue }
    }

    /// Acceptance-specified capitalization alias; the stored JSON remains snake_case.
    var homeownerSignaturePNG: Data? {
        get { homeownerSignaturePng }
        set { homeownerSignaturePng = newValue }
    }

    // MARK: Init

    init(id: UUID = UUID(),
         originJobId: String,
         originInspectionId: String? = nil,
         originEstimateId: String? = nil,
         homeownerName: String,
         projectAddress: String,
         lineItems: [ProposalLineItem],
         taxRate: Double = 0.0825,
         depositPct: Double = 0.30,
         scopeNarrative: String = "",
         warrantyTerms: String = "GAF 25-year shingle, 2-year workmanship",
         paymentSchedule: String = "30% deposit on signing, balance on completion",
         validUntil: Date = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now,
         status: ProposalStatus = .draft,
         homeownerSignaturePng: Data? = nil,
         sentTo: String? = nil,
         sentChannel: ProposalSentChannel? = nil,
         sentAt: Date? = nil,
         viewedAt: Date? = nil,
         signedAt: Date? = nil,
         declinedAt: Date? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.originJobId = originJobId
        self.originInspectionId = originInspectionId ?? originJobId
        self.originEstimateId = originEstimateId
        self.homeownerName = homeownerName
        self.projectAddress = projectAddress
        self.lineItems = lineItems
        self.taxRate = taxRate
        self.depositRate = depositPct
        self.scopeNarrative = scopeNarrative
        self.warrantyTerms = warrantyTerms
        self.paymentSchedule = paymentSchedule
        self.validUntil = validUntil
        self.status = status
        self.homeownerSignaturePng = homeownerSignaturePng
        self.sentTo = sentTo
        self.sentChannel = sentChannel
        self.sentAt = sentAt
        self.viewedAt = viewedAt
        self.signedAt = signedAt
        self.declinedAt = declinedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case originJobId         = "origin_job_id"
        case originInspectionId  = "origin_inspection_id"
        case originEstimateId    = "origin_estimate_id"
        case homeownerName       = "homeowner_name"
        case projectAddress      = "project_address"
        case lineItems           = "line_items"
        case taxRate             = "tax_rate"
        case depositRate         = "deposit_rate"
        case legacyDepositPct    = "deposit_pct"
        case scopeNarrative      = "scope_narrative"
        case warrantyTerms       = "warranty_terms"
        case paymentSchedule     = "payment_schedule"
        case validUntil          = "valid_until"
        case status
        case homeownerSignaturePng = "homeowner_signature_png"
        case sentTo              = "sent_to"
        case sentChannel         = "sent_channel"
        case sentAt              = "sent_at"
        case viewedAt            = "viewed_at"
        case signedAt            = "signed_at"
        case declinedAt          = "declined_at"
        case createdAt           = "created_at"
        case updatedAt           = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedJobId = try c.decodeIfPresent(String.self, forKey: .originJobId)
        let decodedInspectionId = try c.decodeIfPresent(String.self, forKey: .originInspectionId)
        originJobId = decodedJobId ?? decodedInspectionId ?? ""
        originInspectionId = decodedInspectionId ?? originJobId
        originEstimateId = try c.decodeIfPresent(String.self, forKey: .originEstimateId)
        homeownerName = try c.decodeIfPresent(String.self, forKey: .homeownerName) ?? ""
        projectAddress = try c.decodeIfPresent(String.self, forKey: .projectAddress) ?? ""
        lineItems = try c.decodeIfPresent([ProposalLineItem].self, forKey: .lineItems) ?? []
        taxRate = try c.decodeIfPresent(Double.self, forKey: .taxRate) ?? 0.0825
        depositRate = try c.decodeIfPresent(Double.self, forKey: .depositRate)
            ?? c.decodeIfPresent(Double.self, forKey: .legacyDepositPct)
            ?? 0.30
        scopeNarrative = try c.decodeIfPresent(String.self, forKey: .scopeNarrative) ?? ""
        warrantyTerms = try c.decodeIfPresent(String.self, forKey: .warrantyTerms)
            ?? "GAF 25-year shingle, 2-year workmanship"
        paymentSchedule = try c.decodeIfPresent(String.self, forKey: .paymentSchedule)
            ?? "30% deposit on signing, balance on completion"
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil)
            ?? (Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
        status = try c.decodeIfPresent(ProposalStatus.self, forKey: .status) ?? .draft
        homeownerSignaturePng = try c.decodeIfPresent(Data.self, forKey: .homeownerSignaturePng)
        sentTo = try c.decodeIfPresent(String.self, forKey: .sentTo)
        sentChannel = try c.decodeIfPresent(ProposalSentChannel.self, forKey: .sentChannel)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        viewedAt = try c.decodeIfPresent(Date.self, forKey: .viewedAt)
        signedAt = try c.decodeIfPresent(Date.self, forKey: .signedAt)
        declinedAt = try c.decodeIfPresent(Date.self, forKey: .declinedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(originJobId, forKey: .originJobId)
        try c.encode(originInspectionId, forKey: .originInspectionId)
        try c.encodeIfPresent(originEstimateId, forKey: .originEstimateId)
        try c.encode(homeownerName, forKey: .homeownerName)
        try c.encode(projectAddress, forKey: .projectAddress)
        try c.encode(lineItems, forKey: .lineItems)
        try c.encode(taxRate, forKey: .taxRate)
        try c.encode(depositRate, forKey: .depositRate)
        try c.encode(scopeNarrative, forKey: .scopeNarrative)
        try c.encode(warrantyTerms, forKey: .warrantyTerms)
        try c.encode(paymentSchedule, forKey: .paymentSchedule)
        try c.encode(validUntil, forKey: .validUntil)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(homeownerSignaturePng, forKey: .homeownerSignaturePng)
        try c.encodeIfPresent(sentTo, forKey: .sentTo)
        try c.encodeIfPresent(sentChannel, forKey: .sentChannel)
        try c.encodeIfPresent(sentAt, forKey: .sentAt)
        try c.encodeIfPresent(viewedAt, forKey: .viewedAt)
        try c.encodeIfPresent(signedAt, forKey: .signedAt)
        try c.encodeIfPresent(declinedAt, forKey: .declinedAt)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
