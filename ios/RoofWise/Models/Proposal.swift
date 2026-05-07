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
    var originJobId: String                  // Inspection.report_id
    var originEstimateId: String?            // SavedEstimate.id (uuid string)
    var homeownerName: String
    var projectAddress: String
    var lineItems: [ProposalLineItem]

    var taxRate: Double                      // 0.0825
    var depositPct: Double                   // 0.30
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
    var depositAmount: Double { total * depositPct }

    // MARK: Init

    init(id: UUID = UUID(),
         originJobId: String,
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
        self.originEstimateId = originEstimateId
        self.homeownerName = homeownerName
        self.projectAddress = projectAddress
        self.lineItems = lineItems
        self.taxRate = taxRate
        self.depositPct = depositPct
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
        case originEstimateId    = "origin_estimate_id"
        case homeownerName       = "homeowner_name"
        case projectAddress      = "project_address"
        case lineItems           = "line_items"
        case taxRate             = "tax_rate"
        case depositPct          = "deposit_pct"
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
}
